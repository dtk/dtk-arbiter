require 'socket'
require 'timeout'

module DTK::Arbiter
  class Worker
    class Generic < self
      require_relative('generic/response_hash')
      require_relative('generic/docker')
      require_relative('generic/native_grpc_daemon')
      require_relative('generic/convert_to_ruby_datatype')

      include NativeGrpcDaemon::Mixin
      include Docker::Mixin

      BASE_DTK_DIR          = '/usr/share/dtk'
      MODULE_DIR            = "#{BASE_DTK_DIR}/modules"

      $queue = []

      Docker::GarbageCollection.run_garbage_collection

      def initialize(message_content, listener)
        super(message_content, listener)

        Log.info "Initializing generic worker"
        Log.info "Environment: #{ENV.inspect}"

        @protocol_version       = get(:protocol_version) || 0

        @provider_type          = get(:provider_type) || UNKNOWN_PROVIDER

        @service_instance       = get(:service_instance)
        @component              = get(:component)
        @module_name            = @component[:module_name]
        @component_name         = "#{@component[:namespace]}:#{@module_name}"

        @attributes             = get(:attributes)
        @provider_attributes    = @attributes[:provider] || raise(Arbiter::MissingParams, "Provider attributes missing.")
        @instance_attributes    = @attributes[:instance]

        @modules                = get(:modules)

        @execution_type         = get(:execution_environment)[:type]
        @dockerfile             = get(:execution_environment)[:docker_file]
        @provider_name_internal = "#{@provider_type}-provider"
        @provider_entrypoint    = "#{MODULE_DIR}/#{@provider_name_internal}/init"

        @task_id                = get(:task_id)

        # Make sure following is prepared
        FileUtils.mkdir_p(MODULE_DIR, mode: 0755) unless File.directory?(MODULE_DIR)
      end

      private :initialize

      def process
        # we need this to pull our modules
        git_server = Config.git_server

        # pulling modules and preparing environment for changes
        Log.info 'Pulling modules from DTK'
        response = Utils::Git.pull_modules(get(:modules), git_server)

        # run the provider
        provider_run_response = invoke_action
        notify(provider_run_response)
      end

      def self.cancel_task(message)
        if message[:agent] == 'cancel_action' && message[:worker] == 'generic'
          task_id = message[:task_id]
          running_containers_queue = $queue.select {|q| q[task_id]}
          running_containers_queue.each do |process|
            $queue.delete_at($queue.index(process) || $queue.length)
            # this will be either a docker container name or PID of the native gRPC daemon
            process_id = process[task_id]
            if process['type'] == 'docker'
              Log.info "Removing container #{process_id} as requested by cancel action"
              Docker::Container.stop_and_remove?(process_id) rescue false
            elsif process['type'] == 'native'
              Log.info "Killing process with a PID of #{process_id} as requested by cancel action"
              Process.kill('HUP', process_id) rescue false
            else
              notify_of_error("Unrecognized process type in cancel task.", :abort_action)
            end
          end
        end
      end

      private

      attr_reader :provider_entrypoint
      
      def invoke_action
        Log.info 'Starting generic worker run'
        # spin up the provider gRPC server
        set_grpc_port!(generate_grpc_port)

        response_hash = 
          if ephemeral?
            invoke_action_when_container
          else

            if dtk_debug_generic_worker?
              require 'byebug'
              require 'byebug/core'
              Byebug.wait_connection = true
              Byebug.start_server 'localhost'
              debugger
            end

            invoke_action_when_native_grpc_daemon
          end

        if response_hash.has_error?
          notify_of_error("#{@provider_type} provider reported the error: #{response_hash.error_message}", :abort_action)
        end
        
        # add the gRPC address as a dynamic attribute
        (response_hash['dynamic_attributes'] ||= {})['grpc_address'] = grpc_address
        response_hash.raw_hash_form # needed because upstead assumes ::Hash objects
      end
      
      def ephemeral?
        @execution_type == 'ephemeral_container'
      end

      def generate_provider_message(attributes, merge_hash, protocol_version)
        converted_attributes = 
          case protocol_version
          when 1
            attributes.inject({}) do |h, (type, attributes_with_metadata)|
            h.merge(type => ConvertToRubyDataype.convert_attributes(attributes_with_metadata))
          end
          else
            attributes
          end
        
        converted_attributes.merge(merge_hash).to_json
      end

      def grpc_host
        @grpc_host ||= arbiter_inside_docker? ? get_arbiter_primary_ip : '127.0.0.1'
      end

      def grpc_port
        @grpc_port || fail("Unexpected that @grpc_port is not set")
      end

      def set_grpc_port!(grpc_port)
        @grpc_port = grpc_port
      end
      
      def grpc_address
        "#{grpc_host}:#{grpc_port}"
      end
      
      def arbiter_inside_docker?
        File.exist?('/.dockerenv')
      end

      def get_arbiter_primary_ip
        route = `/sbin/ip route`
        ip = route.split[2]
        ip
      end

      # returns response_hash
      def grpc_call_to_invoke_action
        # send a message to the gRPC provider server/daemon
        stub = GrpcHelper.arbiter_service_stub(grpc_address, :this_channel_is_insecure, :timeout => 240)
        
        provider_message = generate_provider_message(@attributes, {:component_name => @component_name, :module_name => @module_name}, @protocol_version) #provider_message_hash.to_json

        Log.info "Sending a message to the gRPC daemon at #{grpc_address}"
        Log.info "Checking to see if grpc port is open:"
        port_check = port_open?(grpc_host, grpc_port)
        Log.info "#{port_check}"
        grpc_json_response = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        Log.info 'gRPC daemon response received'
        ResponseHash.create_from_json(grpc_json_response)
      end

      DEBUG_ATTRIBUTE = 'dtk_debug_generic_worker'
      def dtk_debug_generic_worker?
        (((@instance_attributes || {})[DEBUG_ATTRIBUTE] || {})[:value] || 'false') == 'true'
      end

      PORT_RANGE = 50000..60000
      def generate_grpc_port
        port = nil
        if ephemeral?
          if port = running_container_port?
            return port
          end
        end
        while port.nil? or port_open?(grpc_host, port) do
          port = rand(PORT_RANGE)
        end
        port
      end

      def port_open?(ip, port, seconds=1)
        ::Timeout::timeout(seconds) do
          begin
            ::TCPSocket.new(ip, port).close
            true
          rescue ::Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            false
          end
        end
      rescue ::Timeout::Error
        false
      end
      
    end
  end
end
