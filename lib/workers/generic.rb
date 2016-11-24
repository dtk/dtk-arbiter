require 'grpc'

require File.expand_path('../../common/worker', __FILE__)

module Arbiter
  module Generic
    class Worker < Common::Worker
      Log.info "Initializing generic worker"

      MODULE_PATH         = "/usr/share/dtk/modules"
      NUMBER_OF_RETRIES   = 5

      def initialize(message_content, listener)
        super(message_content, listener)

        @provider_type    = get(:provider_type) || UNKNOWN_PROVIDER
        @version_context  = get(:version_context)

        @provider_entrypoint = "#{MODULE_PATH}/dtk-provider-#{@provider_type}/init"
        @pidfile_path = "/tmp/dtk-provider-#{@provider_type}.pid"

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
        provider_run_response.merge!(success_response)

        notify(provider_run_response)
      end

      def run()
        # spin up the provider gRPC server
        start_daemon

        response = {}
        response
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
            exec @provider_entrypoint
          end
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