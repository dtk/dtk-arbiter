require 'eventmachine'

module DTK
  module Arbiter
    module Listener
      include ::EM::Protocols::Stomp

      require_relative('worker/generic')
      
      Log.debug "Initializing arbiter"

      THREADS_PER_CPU = 4

      # returns number of CPU cores available
      def cpu_count
        return Java::Java.lang.Runtime.getRuntime.availableProcessors if defined? Java::Java
        return File.read('/proc/cpuinfo').scan(/^processor\s*:/).size if File.exist? '/proc/cpuinfo'
        require 'win32ole'
        WIN32OLE.connect("winmgmts://").ExecQuery("select * from Win32_ComputerSystem").NumberOfProcessors
      rescue LoadError
        Integer `sysctl -n hw.ncpu 2>/dev/null` rescue 1
      end
      
      def connection_completed
        connect :login => Config.stomp_username, :passcode => Config.stomp_password
        @thread_pool = {}
        @thread_pool_max_size = (cpu_count * THREADS_PER_CPU)
        @thread_queue = []
        @puppet_apply_running  = false
        @puppet_apply_queue = []
        Log.info "Arbiter listener has been successfully started. Listening to #{Config.full_url} ..."
      end
      
      def unbind
        Log.info "Connection to STOMP server #{Config.full_url} is closed."
        
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
        Log.debug "Received STOMP message with a header: #{msg.header}"
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
          process_message(msg)
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
      
        Log.info("Sending reply to '#{Config.outbox_queue}': #{message}")
        send(Config.outbox_queue, encoded_message)
      end
      
      private

      ##
      # After arbiter sets up successful connection, we send a heartbeat with pbuilder_id. DTK Server on the other side will be listening to this
      # and mark this node as up and running
      #
      def send_hearbeat
        # we do not have sucess
        update({ :status => :succeeded }, 1, false, true)
        Log.debug "Heartbeat has been sent to '#{Config.outbox_queue}' for instance '#{Arbiter::PBUILDER_ID}' ..."
      end

      def process_message(msg)
        begin
          # decode message
          decoded_message = decode(msg.body)
        rescue Exception => ex
          Log.fatal("Error decrypting STOMP message, will have to ignore this message. Error: #{ex.message}")
          return
        end
        # check pbuilder id
        unless check_pbuilderid?(decoded_message[:pbuilderid])
          Log.debug "Discarding message pbuilder '#{decoded_message[:pbuilderid]}', not ment for this consumer '#{Arbiter::PBUILDER_ID}'"
          return
        end
          
        # determine the worker to handle payload
        Log.debug "Received message: #{Utils::Sanitize.sanitize_message(decoded_message)}"
        unless worker = Worker.create?(decoded_message, self)
          unless ::DTK::Arbiter::Worker::Generic.cancel_task(decoded_message)
            unless handle_cancel_action?(decoded_message)
              # no worker?! drop the message
              Log.warn "Not able to resolve desired worker from given message, dropping message."
            end
          end
          return
        end
          
        # no request id?! drop the message
        unless decoded_message[:request_id]
          Log.warn "Not able to resolve request id from given message, dropping message."
          return
        end

          
        ##
        # If there is puppet apply running than queue this execution, else just run concurrentl
        #
        if worker.is_puppet_apply? && @puppet_apply_running
          Log.info "Arbiter worker has been queued #{worker} with request id #{worker.request_id}, waiting for execution ..."
          @puppet_apply_queue.push(worker)
        # if there are already @thread_pool_max_size tasks running, add to queue instead of executing immediately
        elsif @thread_pool.size > 2
          Log.info "Arbiter worker has been queued #{worker} with request id #{worker.request_id}, waiting for execution ..."
          @thread_queue.push(worker)
        else
          Log.info "Arbiter worker has been chosen #{worker} with request id #{worker.request_id}, starting work ..."
          run_task_concurrently(worker)
        end
      end

      def run_task_concurrently(worker)
        # start new EM thread to handle this work
        ::EM.defer(proc do
          begin
            # register thread for cancel
            @thread_pool[worker.request_id] = Thread.current
            
            # we lock concurrency for puppet apply
            @puppet_apply_running = true if worker.is_puppet_apply?
            
            worker.process
          rescue ArbiterError => e
            worker.notify_of_error(e.message, e.error_type)
          rescue Exception => e
            remove_container if e.message.include?("Deadline Exceeded")
            Log.fatal(e.message, e.backtrace)
            worker.notify_of_error(e.message, :internal)
          ensure
            # we unlock concurrency and trigger next puppet apply task
            if worker.is_puppet_apply? && @puppet_apply_running
              @puppet_apply_running = false
              unless @puppet_apply_queue.empty?
                queued_instance = @puppet_apply_queue.pop
                Log.info "Arbiter worker has been un-queued #{queued_instance} with request id #{queued_instance.request_id}, starting work ..."
                run_task_concurrently(queued_instance)
              end
            end
            unless @thread_queue.empty?
              queued_worker = @thread_queue.pop
              Log.info "Arbiter worker has been un-queued #{queued_worker} with request id #{queued_worker.request_id}, starting work ..."
              run_task_concurrently(queued_worker)
            end
          end
        end)
      end
      
      def remove_container        
        container_name = ""
        $queue.each { |q| container_name = q[$task_id] if q.key?($task_id) } 
        DTK::Arbiter::Worker::Generic::Docker::Container.stop_and_remove?(container_name)
      end

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
      
      def handle_cancel_action?(message)
        case message[:agent]
        when 'cancel_action'
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

