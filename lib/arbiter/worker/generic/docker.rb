module DTK::Arbiter
  class Worker::Generic
    module Docker
      require_relative('docker/garbage_collection')
      require_relative('docker/container')
      require_relative('docker/image')

      module OpenPortCheck
        NUMBER_OF_RETRIES = 10
        TIME_BETWEEN_RETRY = 1
      end
      
      module Mixin
        private

        #returns ResponseHash
        def invoke_action_when_container
          # spin up the gRPC daemon in a docker container
          # if ok sets docker_image_tag, if failure docker_image_tag is nil and error_msg is set
          docker_image_tag, error_msg = build_and_start_docker_container 
          if docker_image_tag.nil?
            response_hash = ResponseHash.error(error_msg: error_msg)
          else
            response_hash = grpc_call_to_invoke_action
            $queue.delete_at($queue.index({@task_id => docker_image_tag}) || $queue.length)
            Container.stop_and_remove?(container_name)
          end
          response_hash
        end

        # if ok sets docker_image_tag, if failure docker_image_tag is nil and error_msg is set
        def build_and_start_docker_container 
          docker_image_tag = container_name
          Log.info "Building docker image #{docker_image_tag}"
          Image.build(@dockerfile, docker_image_tag)

          Log.info "Starting docker container #{docker_image_tag} on port #{grpc_port}"
          status, error_msg = start_daemon_docker?
          if status == :failed
            [nil, error_msg]
          else
            $queue << {@task_id => docker_image_tag}
            docker_image_tag
          end
        end

        # returns :ok or :failed and if failed [:failed, err_msg] is returned
        def start_daemon_docker?
          return :ok if Container.running?(container_name)

          begin
            Container.stop_and_remove?(container_name) unless $queue.include?({@task_id => container_name})
          rescue => e
            return [:failed, "Failed to remove existing docker container '#{container_name}' (#{e.message})"]
          end

          container = nil
          begin
            Container.create_and_start(container_name, grpc_host, grpc_port)
          rescue => e
            return [:failed, "Failed to create and start the docker container '#{container_name}' (#{e.message})"]
          end

          tries ||= Docker::OpenPortCheck::NUMBER_OF_RETRIES
          until (tries -= 1).zero?
            sleep Docker::OpenPortCheck::TIME_BETWEEN_RETRY
            break if port_open?(grpc_host, grpc_port)
          end
          unless port_open?(grpc_host, grpc_port)
            return [:failed, "Failed to start docker gRPC daemon"]
          end
          :ok
        end

        def running_container_port?
          Container.running_port?(container_name)
        end

        def container_name
          @container_name ||= "#{@service_instance}-#{@component_name}".tr(':','-')
        end

      end
    end
  end
end
