module DTK::Arbiter
  class Worker::Generic
    module NativeGrpcDaemon
      NUMBER_OF_RETRIES = 5
      TIME_BETWEEN_RETRY = 1

      module Mixin
        private

        #returns ResponseHash
        def invoke_action_when_native_grpc_daemon
          # spin up the gRPC daemon on the OS
          status = start_grpc_daemon_with_retries
          response_hash = nil
          if status == :failed
            response_hash = ResponseHash.error
          else
            response_hash = grpc_call
            stop_grpc_daemon
          end
        end

        # returns :ok or :failed
        def start_grpc_daemon_with_retries
          tries ||= NativeGrpcDaemon::NUMBER_OF_RETRIES
          status = :failed
          until (tries -= 1).zero?
            status = start_grpc_daemon
            return :ok if status == :ok
            sleep NativeGrpcDaemon::TIME_BETWEEN_RETRY
          end
          notify_of_error("Failed to start #{provider_type} gRPC daemon", :abort_action)
          :failed
        end

        # returns :ok or :failed
        def start_grpc_daemon
          # check if provider daemon is already running
          if File.exist?(@pidfile_path)
            pid = File.read(@pidfile_path).to_i
            return :ok if (Process.getpgid(pid) rescue false)
          end
          # if not, start it
          begin
            puts 'starting daemon'
            daemon_job = fork do
              ::Bundler.with_clean_env do
                exec @provider_entrypoint
              end
            end
            sleep 2
            :ok
          rescue
            :failed
          end
        end
      
        def stop_grpc_daemon
          pid = File.read(@pidfile_path).to_i
          Process.kill("HUP", pid)
        end

      end
    end
  end
end
