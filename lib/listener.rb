require 'eventmachine'
require 'base64'
require 'yaml'

require File.expand_path('../common/worker', __FILE__)


Dir["lib/workers/*.rb"].each do |file_path|
  require File.expand_path("../../#{file_path}", __FILE__)
end

module Arbiter
  module Listener
    include EM::Protocols::Stomp

    def connection_completed
      connect :login => Utils::Config.stomp_username, :passcode => Utils::Config.stomp_password
      @thread_pool = {}
    end

    def receive_msg msg
      if "CONNECTED".eql?(msg.command)
        # success connecting to stomp
        subscribe(Utils::Config.inbox_topic)
        Log.debug "Connected to STOMP and subscribed to topic '#{Utils::Config.inbox_topic}'"
      elsif "ERROR".eql?(msg.command)
        # error connecting to stomp
        Log.fatal "Not able to connect to STOMP, reason: #{msg.header['message']}. Stopping listener now ..."
        exit(1)
      else
        # decode message
        original_message = decode64(msg.body)

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
          # register thread for cancel
          @thread_pool[original_message[:request_id]] = Thread.current

          # start work
          sleep(100)
          target_instance.process()
        end)
      end
    end

    def update(results, request_id)
      raise "Request_id is mandatory param" unless request_id

      message = {
        body: {
          data: { results: results },
          request_id: request_id,
          pbuilderid: Arbiter::PBUILDER_ID,
          status: :ok,
          statuscode: 0
        }
      }

      # remove from thread pull
      @thread_pool.delete(request_id)

      Log.debug("Sending reply to '#{Utils::Config.outbox_topic}': #{message}")
      send(Utils::Config.outbox_topic, encode64(message))
    end


  private

    def encode64(message)
      Base64.encode64(message.to_yaml)
    end

    def cancel_worker(request_id)
      @thread_pool[request_id].kill
      @thread_pool.delete(request_id)
    end

    def decode64(message)
      decoded_message = Base64.decode64(message)
      YAML.load(decoded_message)
    end

    def worker_factory(message)
      target_agent = message[:agent] || 'action'

      return case target_agent
        when 'action_agent'
          ::Arbiter::Action::AgentWorker.new(message, self)
        when 'cancel_agent'
          Log.info "Sending cancel signal to worker for request (ID: '#{request_id}')"
          cancel_agent(message[:request_id])
        else
          nil
        end
    end


  end
end