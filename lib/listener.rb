require 'eventmachine'
require 'base64'
require 'yaml'
require 'openssl'

require File.expand_path('../common/worker', __FILE__)
require File.expand_path('../common/logger', __FILE__)
require File.expand_path('../common/error', __FILE__)
require File.expand_path('../utils/ssh_cipher', __FILE__)

Dir["lib/workers/*.rb"].each do |file_path|
  require File.expand_path("../../#{file_path}", __FILE__)
end

module Arbiter
  module Listener
    include EM::Protocols::Stomp

    Log.debug "Initiliazing arbiter"

    def connection_completed
      connect :login => Utils::Config.stomp_username, :passcode => Utils::Config.stomp_password
      @thread_pool = {}
      Log.debug "connection completed"
    end

    def receive_msg msg
      Log.debug "Trying to receive_msg"
      if "CONNECTED".eql?(msg.command)
        # success connecting to stomp
        subscribe(Utils::Config.inbox_topic)
        Log.debug "Connected to STOMP and subscribed to topic '#{Utils::Config.inbox_topic}'"
      elsif "ERROR".eql?(msg.command)
        # error connecting to stomp
        Log.fatal("Not able to connect to STOMP, reason: #{msg.header['message']}. Stopping listener now ...", nil)
        exit(1)
      else
        # decode message
        Log.debug "Decoding message"
        original_message = decode(msg.body)

        # check pbuilder id
        Log.debug "Checking message for pbuilderid"
        unless check_pbuilderid?(original_message[:pbuilderid])
          Log.debug "Discarding message pbuilder '#{original_message[:pbuilderid]}', not ment for this consumer '#{Arbiter::PBUILDER_ID}'"
          return
        end

        # determine the worker to handle payload
        Log.debug "Received message: #{original_message}"
        target_instance = worker_factory(original_message)

        # no worker?! drop the message
        unless target_instance
          Log.warn "Not able to resolve desired worker from given message, dropping message."
          return
        end

        # no request id?! drop the message
        unless original_message[:request_id]
          Log.warn "Not able to resolve request id from given message, dropping message."
          return
        end

        Log.info "Arbiter worker has been choosen #{target_instance} with request id #{original_message[:request_id]}, starting work ..."

        # start new EM thread to handle this work
        EM.defer(proc do
          begin
            # register thread for cancel
            @thread_pool[original_message[:request_id]] = Thread.current

            target_instance.process()
          rescue ArbiterError => e
            target_instance.notify_of_error(e.message, e.error_type)
          rescue Exception => e
            Log.fatal(e.message, e.backtrace)
          end
        end)
      end
    end

    def update(results, request_id, error_response = false)
      raise "Param request_id is mandatory" unless request_id
      statuscode = error_response ? 1 : 0
      status     = error_response ? :failed : :succeeded

      message = {
        requestid: request_id,
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

      mesage[:body].merge!(retrieve_error_info(results)) if error_response

      # remove from thread pull
      @thread_pool.delete(request_id)

      Log.debug("Sending reply to '#{Utils::Config.outbox_topic}': #{message}")
      send(Utils::Config.outbox_topic, encode(message))
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
      # this will work on regexp string and regular strings - older version of Regexp does not handle extra // that well
      regexp = Regexp.compile(pbuilderid.gsub(/[\/]/,''))
      !regexp.match(Arbiter::PBUILDER_ID).nil?
    end

    def encode(message)
      encrypted_message, ekey, esecret = Utils::SSHCipher.encrypt_sensitive(message)
      Marshal.dump({ :payload => encrypted_message, :ekey => ekey, :esecret => esecret })
    end

    def cancel_worker(request_id)
      @thread_pool[request_id].kill
      @thread_pool.delete(request_id)
    end

    def decode(message)
      encrypted_message = Marshal.load(message)

      decoded_message = Utils::SSHCipher.decrypt_sensitive(encrypted_message[:payload], encrypted_message[:ekey], encrypted_message[:esecret])
      decoded_message
    end

    def worker_factory(message)
      target_agent = message[:agent] || 'action'

      return case target_agent
        when 'secure_agent', 'git_access'
          ::Arbiter::Secure::Worker.new(message, self)
        when 'action_agent'
          ::Arbiter::Action::Worker.new(message, self)
        when 'system_agent'
          ::Arbiter::System::Worker.new(message, self)
        when 'discovery'
          ::Arbiter::Discovery::Worker.new(message, self)
        when 'puppet_apply'
          ::Arbiter::Puppet::Worker.new(message, self)
        when 'docker_agent'
          ::Arbiter::Docker::Worker.new(message, self)
        when 'cancel_agent'
          Log.info "Sending cancel signal to worker for request (ID: '#{request_id}')"
          cancel_agent(message[:request_id])
        else
          nil
        end
    end


  end
end
