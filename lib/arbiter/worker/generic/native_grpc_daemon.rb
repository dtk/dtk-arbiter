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
          return ResponseHash.error(error_msg: provider_error_message) unless execute_bash(@bash_script)
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

        def provider_error_message
          case @provider_type
          when 'ruby'
            'An error was encountered while installing gem dependencies. Please check dtk-arbiter log for more details.'
          else
            "Failed to execute #{@provider_type} provider dependencies. Please check dtk-arbiter log for more details."
          end
        end  
      
      NUMBER_OF_RETRIES  = 10
      TIME_BETWEEN_RETRY = 1
    
      # returns daemon_process_id or [nil, error_msg]
      def start_grpc_daemon_with_retries(provider_entrypoint, grpc_port, grpc_address, grpc_host, task_id)
        port_tries ||= NUMBER_OF_RETRIES
        tries = @failure_attempts
        sleep_between_retries = @failure_sleep
        status = :failed
        error_msg = [nil, "Failed to start gRPC daemon natively on #{grpc_address}"]

        begin
          until (port_tries -= 1).zero?
            if daemon_process_id = start_grpc_daemon?(provider_entrypoint, grpc_port, task_id)
              Log.info "Started gRPC daemon natively on #{grpc_address}"
              port_tries ||= NUMBER_OF_RETRIES
              until (port_tries -= 1).zero?
                sleep TIME_BETWEEN_RETRY
                break if port_open?(grpc_host, grpc_port)
              end
              unless port_open?(grpc_host, grpc_port)
                stop_grpc_daemon(daemon_process_id, task_id)
                raise ActionAbort, error_msg[1]
              end
              return daemon_process_id
            else
              sleep TIME_BETWEEN_RETRY
            end
          end
        rescue ActionAbort => e
          if (tries -= 1) > 0
            Log.warn("Re-trying gRPC daemon native start because of error: #{e.message}, retries left: #{tries}")
            sleep(sleep_between_retries)
            retry
          end
          error_msg
        end
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
