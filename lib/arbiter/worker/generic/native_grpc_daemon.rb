module DTK::Arbiter
  class Worker::Generic
    module NativeGrpcDaemon
      module Mixin
        private

        #returns ResponseHash
        def invoke_action_when_native_grpc_daemon
          # spin up the gRPC daemon on the OS
          daemon_process_id, error_msg = NativeGrpcDaemon.start_grpc_daemon_with_retries(provider_entrypoint, grpc_port, grpc_address)
          unless daemon_process_id
            ResponseHash.error(error_msg)
          else
            begin
              grpc_call_to_invoke_action
            ensure
              NativeGrpcDaemon.stop_grpc_daemon(daemon_process_id)
            end
          end
        end

      end
      
      NUMBER_OF_RETRIES  = 5
      TIME_BETWEEN_RETRY = 1
      PAUSE_AFTER_START  = 2 # in seconds
    
      # returns daemon_process_id or [nil, error_msg]
      def self.start_grpc_daemon_with_retries(provider_entrypoint, grpc_port, grpc_address)
        tries ||= NUMBER_OF_RETRIES
        status = :failed
        until (tries -= 1).zero?
          if daemon_process_id = start_grpc_daemon?(provider_entrypoint, grpc_port)
            Log.info "Started gRPC daemon natively on #{grpc_address}"
            return daemon_process_id
          else
            sleep TIME_BETWEEN_RETRY
          end
        end
        [nil, "Failed to start gRPC daemon natively on #{grpc_address}"]
      end
      
      def self.stop_grpc_daemon(daemon_process_id)
        Process.kill('HUP', daemon_process_id) rescue nil
      end
      
      private
      
    # returns daemon_process_id  or nil
      def self.start_grpc_daemon?(provider_entrypoint, grpc_port)
        begin
          daemon_process_id = fork do
            ::Bundler.with_clean_env do
              exec provider_entrypoint, grpc_port.to_s
          end
          end
          sleep PAUSE_AFTER_START
        daemon_process_id
        rescue
          nil
        end
      end

    end
  end
end
