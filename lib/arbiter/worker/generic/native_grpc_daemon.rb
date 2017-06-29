require 'fileutils'
require 'tempfile'

module DTK::Arbiter
  class Worker::Generic
    module NativeGrpcDaemon
      module Mixin
        private

        #returns ResponseHash
        def invoke_action_when_native_grpc_daemon
          # run the bash script received in the message
          ResponseHash.error("Failed to execute provider script") unless execute_bash(@bash_script)
          # spin up the gRPC daemon on the OS
          daemon_process_id, error_msg = start_grpc_daemon_with_retries(provider_entrypoint, grpc_port, grpc_address, grpc_host, task_id)
          unless daemon_process_id
            ResponseHash.error(error_msg: error_msg)
          else
            begin
              grpc_call_to_invoke_action
            ensure
              stop_grpc_daemon(daemon_process_id, task_id)
            end
          end
        end

      
      
      NUMBER_OF_RETRIES  = 15
      TIME_BETWEEN_RETRY = 2
    
      # returns daemon_process_id or [nil, error_msg]
      def start_grpc_daemon_with_retries(provider_entrypoint, grpc_port, grpc_address, grpc_host, task_id)
        tries ||= NUMBER_OF_RETRIES
        status = :failed
        error_msg = [nil, "Failed to start gRPC daemon natively on #{grpc_address}"]
        until (tries -= 1).zero?
          if daemon_process_id = start_grpc_daemon?(provider_entrypoint, grpc_port, task_id)
            Log.info "Started gRPC daemon natively on #{grpc_address}"
            tries ||= NUMBER_OF_RETRIES
            until (tries -= 1).zero?
              Log.debug "Checking gRPC daemon port, retry #: #{tries}"
              Log.debug "gRPC status check: #{grpc_status_check}"
              sleep TIME_BETWEEN_RETRY
              break if port_open?(grpc_host, grpc_port) || grpc_status_check
            end
            unless port_open?(grpc_host, grpc_port)
              stop_grpc_daemon(daemon_process_id, task_id)
              return error_msg
            end
            return daemon_process_id
          else
            sleep TIME_BETWEEN_RETRY
          end
        end
        error_msg
      end
      
      def stop_grpc_daemon(daemon_process_id, task_id)
        $queue.delete_at($queue.index({task_id => daemon_process_id, 'type' => 'native'}) || $queue.length) unless $queue.empty?
        Process.kill('SIGTERM', daemon_process_id) rescue nil
        Process.detach(daemon_process_id)
        Log.info("Stopped gRPC daemon PID: #{daemon_process_id}")
      end
      
      private
      
    # returns daemon_process_id  or nil
      def start_grpc_daemon?(provider_entrypoint, grpc_port, task_id)
        begin
          daemon_process_id = fork do
            ::Bundler.with_clean_env do
              exec provider_entrypoint, grpc_port.to_s
          end
          end
        $queue << {task_id => daemon_process_id, 'type' => 'native'}
        daemon_process_id
        rescue
          nil
        end
      end

      def execute_bash(script)
        # write the bash script to a temp file
        # make it executable
        # and run it
        bash_temp_file = Tempfile.new('bashscript.sh')
        File.write(bash_temp_file, script)
        FileUtils.chmod('u+x', bash_temp_file)
        bash_temp_file.close
        Log.info("Executing script: #{bash_temp_file.path}")
        response = ''
        ::Bundler.with_clean_env do
          response = system(bash_temp_file.path)
        end
        bash_temp_file.unlink
        response
      end
      end

    end
  end
end
