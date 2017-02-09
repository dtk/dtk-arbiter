require 'eventmachine'

module DTK
  module Arbiter
    module Listener
      include ::EM::Protocols::Stomp
      
      Log.debug "Initializing arbiter"
      
      def connection_completed
        connect :login => Config.stomp_username, :passcode => Config.stomp_password
        @thread_pool = {}
        @puppet_apply_running  = false
        @puppet_apply_queue = []
        Log.info "Arbiter listener has been successfully started. Listening to #{Config.full_url} ..."
      end
      
      def unbind
        Log.error "Connection to STOMP server #{Config.full_url} failed, reconnecting in #{Config.connect_time} seconds ..."
        
        @connect_retries ||= Config.connect_retries
        
        if @connect_retries > 0
          ::EM.add_timer(Config.connect_time) do
            @connect_retries -= 1
            Log.info "Reconnecting to #{Config.full_url}, retries left: #{@connect_retries}"
            reconnect Config.stomp_url, Config.stomp_port
          end
        else
          Log.fatal "Not able to connect to STOMP server #{Config.full_url} after #{Config.connect_retries}, exiting arbiter ..."
          raise ArbiterExit , "Not able to connect to STOMP server #{Config.full_url}"
        end
      end
      
      def receive_msg msg
        if "CONNECTED".eql?(msg.command)
          # success connecting to stomp
          subscribe(Config.inbox_topic)
          Log.debug "Connected to STOMP and subscribed to topic '#{Config.inbox_topic}'"
          send_hearbeat
          
          ::EM.add_periodic_timer(Config.pulse_interval) do
            # send pulse message to keep STOMP connection alive
            update_pong
          end
          Log.info "Activated pulse interval, connection to STOMP is refreshed every #{Config.pulse_interval} seconds."
        elsif "ERROR".eql?(msg.command)
          # error connecting to stomp
          Log.fatal("Not able to connect to STOMP, reason: #{msg.header['message']}. Stopping listener now ...", nil)
          exit(1)
        else
          begin
            # decode message
            original_message = decode(msg.body)
          rescue Exception => ex
            Log.fatal("Error decrypting STOMP message, will have to ignore this message. Error: #{ex.message}")
            return
          end
          # check pbuilder id
          unless check_pbuilderid?(original_message[:pbuilderid])
            Log.debug "Discarding message pbuilder '#{original_message[:pbuilderid]}', not ment for this consumer '#{Arbiter::PBUILDER_ID}'"
            return
          end
          
          # determine the worker to handle payload
          Log.debug "Received message: #{Utils::Sanitize.sanitize_message(original_message)}"
          unless worker = create_worker?(original_message)
            unless handle_cancel_action?(message)
              # no worker?! drop the message
              Log.warn "Not able to resolve desired worker from given message, dropping message."
            end
            return
          end
        end
          
        # no request id?! drop the message
        unless original_message[:request_id]
          Log.warn "Not able to resolve request id from given message, dropping message."
          return
        end
          
        ##
        # If there is puppet apply running than queue this execution, else just run concurrentl
        #
        if worker.is_puppet_apply? && @puppet_apply_running
          Log.info "Arbiter worker has been queued #{worker} with request id #{worker.request_id}, waiting for execution ..."
          @puppet_apply_queue.push(worker)
        else
          Log.info "Arbiter worker has been chosen #{worker} with request id #{worker.request_id}, starting work ..."
          run_task_concurrently(worker)
        end
      end

      def run_task_concurrently(worker)
        # start new EM thread to handle this work
        ::EM.defer proc do
          begin
            # register thread for cancel
            @thread_pool[worker.request_id] = Thread.current
            
            # we lock concurrency for puppet apply
            @puppet_apply_running = true if worker.is_puppet_apply?
            
            worker.process
          rescue ArbiterError => e
            worker.notify_of_error(e.message, e.error_type)
          rescue Exception => e
            Log.fatal(e.message, e.backtrace)
            worker.notify_of_error(e.message, :internal)
          ensure
            # we unluck concurrency and trigger next puppet apply task
            if worker.is_puppet_apply? && @puppet_apply_running
              @puppet_apply_running = false
              unless @puppet_apply_queue.empty?
                queued_instance = @puppet_apply_queue.pop
                Log.info "Arbiter worker has been un-queued #{queued_instance} with request id #{queued_instance.request_id}, starting work ..."
                run_task_concurrently(queued_instance)
              end
            end
          end
        end
      end
      
      def update_pong(request_id = 1)
        message = {
          request_id: request_id,
          pbuilderid: Arbiter::PBUILDER_ID,
          pong: true,
          heartbeat: true
        }
        
        Log.debug("Sending pong response to '#{Config.outbox_queue}'")
        send(Config.outbox_queue, encode(message))
      end
      
      def update(results, request_id, error_response = false, heartbeat = false)
        raise "Param request_id is mandatory" unless request_id
        statuscode = error_response ? 1 : 0
        status     = error_response ? :failed : :succeeded
        
        message = {
          requestid: request_id,
          heartbeat:  heartbeat,
          pong: false,
          pbuilderid: Arbiter::PBUILDER_ID,
          body: {
            request_id: request_id,
            statuscode: statuscode,
            status: status,
            data: {
              data: results,
              status: status,
              pbuilderid: Arbiter::PBUILDER_ID,
              statuscode: statuscode
            }
          }
        }
        
        message[:body].merge!(retrieve_error_info(results)) if error_response
        
        # remove from thread pull
        @thread_pool.delete(request_id)
        
      begin
        encoded_message = encode(message)
      rescue Exception => ex
        Log.fatal("Error encrypting STOMP message, will have to ignore this message. Error: #{ex.message}")
        return
      end
      
        Log.debug("Sending reply to '#{Config.outbox_queue}': #{message}")
        send(Config.outbox_queue, encoded_message)
      end
      
      ##
      # After arbiter sets up successful connection, we send a heartbeat with pbuilder_id. DTK Server on the other side will be listening to this
      # and mark this node as up and running
      #
    
      def send_hearbeat
        # we do not have sucess
        update({ :status => :succeeded }, 1, false, true)
        Log.debug "Heatbeat has been sent to '#{Config.outbox_queue}' for instance '#{Arbiter::PBUILDER_ID}' ..."
      end
      
      private
      
      ##
      # This message parses out result to add to body more error info, to be in line with our legacy code on server
      #
      
      def retrieve_error_info(results)
        {
          error_type: results.first[:type],
          statusmsg: results.first[:error]
        }
      end
      
      def check_pbuilderid?(pbuilderid)
        # this will work on regexp string and regular strings - older version of Regexp does not handle extra / that well
        # we are removing '/' from begining / end string so that regexp compailes properly
        regexp = Regexp.compile(pbuilderid.gsub(/(^\/|\/$)/,''))
        !regexp.match(Arbiter::PBUILDER_ID).nil?
      end
      
      def encode(message)
        encrypted_message, ekey, esecret = Utils::SSHCipher.encrypt_sensitive(message)
        Marshal.dump({ :payload => encrypted_message, :ekey => ekey, :esecret => esecret })
      end
      
      def decode(message)
        encrypted_message = Marshal.load(message)
        
        decoded_message = Utils::SSHCipher.decrypt_sensitive(encrypted_message[:payload], encrypted_message[:ekey], encrypted_message[:esecret])
        decoded_message
    end
      
      def create_worker?(message)
        Worker.create?(message, self) ||  handle_cancel_action?(target_agent, message)
      end
    
      def handle_cancel_action?(message)
        case message[:agent]
        when 'cancel_agent', 'puppet_cancel'
          Log.info "Sending cancel signal to worker for request (ID: '#{message[:request_id]}')"
          cancel_worker(message[:request_id])
          true
        end
      end
      
      def cancel_worker(request_id)
        if request_id_proc = @thread_pool[request_id]
          request_id_proc.kill
          @thread_pool.delete(request_id)
          Log.info "Success canceling  worker for request (ID: '#{request_id}')"
        end
      end
    
    end
  end
end

