require 'grpc'
require 'json'

require File.expand_path('../../common/worker', __FILE__)
require File.expand_path('../../dtkarbiterservice_services_pb', __FILE__)
require File.expand_path('../../docker/commander', __FILE__)

module Arbiter
  module Generic
    class Worker < Common::Worker
      Log.info "Initializing generic worker"

      MODULE_PATH         = "/usr/share/dtk/modules"
      NUMBER_OF_RETRIES   = 5

      def initialize(message_content, listener)
        super(message_content, listener)

        @provider_type    = get(:provider_type) || UNKNOWN_PROVIDER
        @provider_data    = get(:provider_data) || NO_PROVIDER_DATA
        @version_context  = get(:version_context)
        @module_name      = get(:module_name)

        @provider_entrypoint = "#{MODULE_PATH}/dtk-provider-#{@provider_type}/init"
        @pidfile_path = "/tmp/dtk-provider-#{@provider_type}.pid"

        @provider_data.first['module_name'] = @module_name

        # Make sure following is prepared
        FileUtils.mkdir_p(MODULE_PATH, mode: 0755) unless File.directory?(MODULE_PATH)
      end

      def process()
        # we need this to pull our modules
        git_server = Utils::Config.git_server

        # pulling modules and preparing environment for changes
        response = Utils::Git.pull_modules(get(:version_context), git_server)

        # finally run puppet execution
        provider_run_response = run()
        #provider_run_response.merge!(success_response)

        notify(provider_run_response)
      end

      def run()
        # spin up the provider gRPC server
        tries ||= NUMBER_OF_RETRIES
        until (tries -= 1).zero?
          break if start_daemon
          sleep 1
        end
        unless start_daemon
          notify_of_error("Failed to start #{provider_type} gRPC daemon", :missing_params)
          return
        end

        # send a message to the gRPC provider server/daemon
        stub = Dtkarbiterservice::ArbiterProvider::Stub.new('localhost:50051', :this_channel_is_insecure)
        providermessage = @provider_data.to_json
        message = stub.process(Dtkarbiterservice::ProviderMessage.new(message: providermessage)).message
        message = JSON.parse(message)

        #::Arbiter::Docker::Worker.new({}, self)

        # if provider returns a message saying that docker execution is required
        # invoke the docker commander
        if message['execution_type'] = 'ephemeral'
          docker_image = nil
          dockerfile = message['dockerfile']
          docker_command = nil

          commander = Docker::Commander.new(nil,                  # @docker_image
                                            nil,                  # @docker_command,
                                            nil,                  # @puppet_manifest,
                                            'ruby',               # @execution_type,
                                            dockerfile,
                                            @module_name,
                                            {},                  # @docker_run_params,
                                            nil)                  # @dynamic_attributes

          commander.run()

          commander.results()
        else
          response = {:message => message}
          response
        end
      end

  private

      def start_daemon()
        # check if provider daemon is already running
        if File.exist?(@pidfile_path)
          pid = File.read(@pidfile_path).to_i
          return true if (Process.getpgid(pid) rescue false)
        end
        # if not, start it
        begin
          puts 'starting daemon'
          daemon_job = fork do
            Bundler.with_clean_env do
              exec @provider_entrypoint
            end
          end
          sleep 2
          true
        rescue
          false
        end
      end

      #def stop_daemon()
        # TO DO
      #end

    end
  end
end