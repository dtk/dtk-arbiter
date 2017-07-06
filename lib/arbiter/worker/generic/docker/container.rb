require 'docker'
module DTK::Arbiter
  module Worker::Generic::Docker
    module Container
      def self.create_and_start(container_name, docker_image, grpc_host, grpc_port, debug_port)
        container = ::Docker::Container.create(create_params_hash(container_name, docker_image, grpc_host, grpc_port, debug_port))
        container.start
        container
      end

      def self.stop_and_remove?(container_name)
        if container = get_container?(container_name)
          container.stop if running?(container)
          container.remove
        end
      end

      def self.running?(container_or_container_name)
        if container = container?(container_or_container_name)
          container.info['State']['Status'] == 'running'
        end
      end

      def self.running_port?(container_name)
        if container = get_container?(container_name)
          port?(container) if running?(container) 
        end
      end
      
      private

      def self.container?(container_or_container_name)
        c = container_or_container_name # alias
        c.kind_of?(String) ? get_container?(c) : c
      end

      def self.get_container?(container_name)
        ::Docker::Container.get(container_name) rescue nil
      end

      def self.create_params_hash(container_name, docker_image, grpc_host, grpc_port, debug_port)
        grpc_port = grpc_port.to_s
        {
          'Image'        => docker_image,
          'name'         => container_name,
          'Tty'          => true, # needed to run byebug when attach
          'OpenStdin'    => true, # needed to run byebug when attach
          'ExposedPorts' => exposed_ports(debug_port),
          'HostConfig'   => host_config(grpc_port, grpc_host, debug_port)
        }
      end  

      def self.host_config(grpc_port, grpc_host, debug_port)
        # if running inside docker, use host volume to mount modules instead of internal module path
        module_dir = ENV['HOST_VOLUME'].nil? ? Worker::Generic::MODULE_DIR : "#{ENV['HOST_VOLUME']}/modules"
        
        {
          'PortBindings' => port_bindings(grpc_port, grpc_host, debug_port),
          'Binds'        => ["#{module_dir}:#{Worker::Generic::MODULE_DIR}"]
        }

      end

      INTERNAL_CONTAINER_GRPC_PORT = '50051/tcp'
      # TO-DO: expose the debug port also
      def self.exposed_ports(debug_port)
        { INTERNAL_CONTAINER_GRPC_PORT => {}, "#{debug_port}/tcp" => {} }
      end

      def self.port_bindings(grpc_port, grpc_host, debug_port)
        bindings = { INTERNAL_CONTAINER_GRPC_PORT => [{ 'HostPort' => grpc_port, 'HostIp' => grpc_host }] }
        debug_bindings = { "#{debug_port}/tcp" => [{ 'HostPort' => debug_port.to_s, 'HostIp' => '0.0.0.0' }] }
        bindings.merge!(debug_bindings) if $breakpoint
        bindings
      end
        
      def self.port?(container)
        container.info['NetworkSettings']['Ports'][INTERNAL_CONTAINER_GRPC_PORT].first['HostPort'] rescue nil
      end
      
    end
  end
end


