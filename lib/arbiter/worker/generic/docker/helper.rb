require 'docker'
module DTK::Arbiter
  module Worker::Generic::Docker
    class Helper
      def initialize(container_name)
        @container_name = container_name
        # dynamically computed
        @got_container = false
        @container     = nil
      end

      def self.build_image(dockerfile, docker_image_tag)
        docker_image = ::Docker::Image.build(dockerfile)
        docker_image.tag('repo' => docker_image_tag, 'force' => true)
        docker_image
      end

      def running_container_port?
        container_port? if container_running?
      end
      
      def stop_and_remove_container?
        if container_running?
          container.stop
        end
        if container_exists?
          container.remove
        end
      end

      def create_container(grpc_host, grpc_port)
        set_container!(::Docker::Container.create(container_params_hash(grpc_host, grpc_port)))
      end

      def container_running?
        container.info['State']['Status'] == 'running' if container_exists?
      end

      private

      attr_reader :container_name

      def container_exists?
        !container.nil?
      end

      def container
        if @got_container
          @container
        else
          container = ::Docker::Container.get(container_name) rescue nil
          set_container!(container)
        end
      end

      def set_container!(container)
        @got_container = true
        @container = container
      end

      def container_params_hash(grpc_host, grpc_port)
        grpc_port = grpc_port.to_s
        {
          'Image'        => container_name,
          'name'         => container_name,
          'Tty'          => true, # needed to run byebug when attach
          'OpenStdin'    => true, # needed to run byebug when attach
          'ExposedPorts' => exposed_ports,
          'HostConfig'   => host_config(grpc_port, grpc_host)
        }
      end  


      def host_config(grpc_port, grpc_host)
        # if running inside docker, use host volume to mount modules instead of internal module path
        module_dir = ENV['HOST_VOLUME'].nil? ? Worker::Generic::MODULE_DIR : "#{ENV['HOST_VOLUME']}/modules"
        
        {
          'PortBindings' => port_bindings(grpc_port, grpc_host),
          'Binds'        => ["#{module_dir}:#{Worker::Generic::MODULE_DIR}"]
        }

      end

      INTERNAL_CONTAINER_GRPC_PORT = '50051/tcp'
      def exposed_ports
        { INTERNAL_CONTAINER_GRPC_PORT => {} }
      end

      def port_bindings(grpc_port, grpc_host)
        { INTERNAL_CONTAINER_GRPC_PORT => [{ 'HostPort' => grpc_port, 'HostIp' => grpc_host }] }
      end
        
      def container_port?
        container.info['NetworkSettings']['Ports'][INTERNAL_CONTAINER_GRPC_PORT].first['HostPort'] rescue nil
      end
      
    end
  end
end
