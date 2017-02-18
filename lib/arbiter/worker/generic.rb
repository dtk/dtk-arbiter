require 'socket'
require 'timeout'

module DTK::Arbiter
  class Worker
    class Generic < self
      require_relative('generic/grpc_helper')
      require_relative('generic/response_hash')
      require_relative('generic/docker')
      require_relative('generic/native_grpc_daemon')

      include NativeGrpcDaemon::Mixin
      include Docker::Mixin

      BASE_DTK_DIR          = '/usr/share/dtk'
      MODULE_DIR            = "#{BASE_DTK_DIR}/modules"

      $queue = []

      Docker::GarbageCollection.run_garbage_collection

      def initialize(message_content, listener)
        super(message_content, listener)

        Log.info "Initializing generic worker"

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
        @pidfile_path           = "/tmp/#{@provider_name_internal}.pid"

        # dyamically set
        @grpc_port = nil

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

      private
      
      def invoke_action
        Log.info 'Starting generic worker run'
        # spin up the provider gRPC server
        @grpc_port = generate_port
        grpc_address = "#{grpc_host}:#{@grpc_port}"

        response_hash = 
          if ephemeral?
            invoke_action_when_container
          else
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
            
      def grpc_host
        @grpc_host ||= arbiter_inside_docker? ? get_arbiter_primary_ip : '127.0.0.1'
      end

      def grpc_port
        @grpc_port || fail("Unexpected that @grpc_port is not set")
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
      def grpc_call
        # send a message to the gRPC provider server/daemon
        stub = GrpcHelper.arbiter_service_stub("#{grpc_host}:#{grpc_port}", :this_channel_is_insecure)
        
        provider_message = generate_provider_message(@attributes, {:component_name => @component_name, :module_name => @module_name}, @protocol_version) #provider_message_hash.to_json

        Log.info 'Sending a message to the gRPC daemon'
        grpc_json_response = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        Log.info 'gRPC daemon response received'
        ResponseHash.create_from_json(grpc_json_response)
      end
      
      def generate_port
        if ephemeral?
          if port = running_container_port?
            return port
          end

          range = 50000..60000
          begin
            port = rand(range)
          end unless port_open?(grpc_host, port)
        end
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
      
      def generate_provider_message(attributes, merge_hash, protocol_version)
        case protocol_version
        when 1
          converted_attributes = attributes.inject({}) do |h, (type, attributes_hash)|
            h.merge(type => attributes_hash.inject({}) { |h, (name, info)| h.merge(name => info[:value]) })
          end
          converted_attributes.merge(merge_hash).to_json
        else
          attributes.merge(merge_hash).to_json
        end
      end

    end
  end
end
