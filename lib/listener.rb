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
      connect :login => ENV['STOMP_USERNAME'], :passcode => ENV['STOMP_PASSWORD']
    end

    def receive_msg msg
      if "CONNECTED".eql?(msg.command)
        subscribe ENV['INBOX_TOPIC']
      elsif "ERROR".eql?(msg.command)
        raise msg.header['message']
      else
        original_message = decode64(msg.body)

        # DEBUG SNIPPET >>> REMOVE <<<
        require 'ap'
        ap "Here is msg"
        ap original_message

        target_instance = worker_factory(original_message)

        EM.defer(proc do
          target_instance.process()
        end)
      end
    end

    def update(results, request_id)
      raise "Request_id is mandatory param" unless request_id
      # DEBUG SNIPPET >>> REMOVE <<<
      require 'ap'
      ap "Sednign reply mcollective.dtk.reply"
      ap results
      # send("#{ENV['OUTBOX_TOPIC']}.#{request_id}", encode64(results))
      send("mcollective.dtk.reply", encode64(results))
    end


  private

    def encode64(message)
      Base64.encode64(message.to_yaml)
    end

    def decode64(message)
      decoded_message = Base64.decode64(message)
      YAML.load(decoded_message)
    end

    def worker_factory(message)
      target_agent = message[:agent] || 'action'

      return case target_agent
        when 'action'
          ::Arbiter::Action::AgentWorker.new(message, self)
        else
          raise "Not able to find target worker for identifier '#{target_agent}', aborting ..."
        end
    end


  end
end