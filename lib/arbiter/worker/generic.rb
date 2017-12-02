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
        @bash_script            = get(:execution_environment)[:bash]
        @provider_name_internal = "#{@provider_type}-provider"
        @provider_entrypoint    = "#{MODULE_DIR}/#{@provider_name_internal}/init"
        @failure_attempts       = get(:failure_attempts) || Config::DEFAULT_FAILURE_ATTEMPTS
        @failure_sleep          = get(:failure_sleep) || Config::DEFAULT_FAILURE_SLEEP
        $breakpoint             = message_content[:breakpoint]
        @debug_port_request     = message_content[:debug_port_request]
        @debug_port_received    = message_content[:debug_port_received]
        #@dtk_debug_port         = @debug_port_received unless @debug_port_received.nil?
        $dtk_debug_port         = @debug_port_received unless @debug_port_received.nil?
        Log.info("Received port from server: #{@debug_port_received}")
        Log.info("Port request is: #{@debug_port_request}")
        Log.info("Current Debug port is: #{@dtk_debug_port}")
        @task_id                = get(:task_id)
        @diff = false 
        if $task_id.nil?
          $task_id = @task_id
          @diff = true
        elsif $task_id != @task_id
          $dtk_debug_port = nil
          @diff = true
          $task_id = @task_id
        elsif $task_id == @task_id
          @diff = false
        end
	#$task_id = @task_id unless @task_id.nil?
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
        dynamically_load_grpc # grpc must be dynamically loaded to avoid bug DTK-2956

        provider_run_response = nil
        tries = max_number_of_retries 
        sleep_between_retries = @failure_sleep
        begin
          provider_run_response = invoke_action
          raise 'gRPC action failed' if provider_run_response['error'] == 'true'
         rescue Exception => e
          if (tries -= 1) > 0
            Log.warn("Re-trying gRPC action because of error: #{e.message}, retries left: #{tries}")
            sleep(sleep_between_retries)
            retry
          end
          # time to give up - sending error response
          raise e
        end

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
              Process.kill('SIGTERM', process_id) rescue false
              Process.detach(process_id)
            else
              notify_of_error("Unrecognized process type in cancel task.", :abort_action)
            end
          end
        end
      end


      #  def self.debug_message(message)
      #   if message[:breakpoint] && message[:worker] == 'generic'
      #     return
      #   else
      #     notify_of_error("Unrecognized process type in cancel task.", :abort_action)
      #   end
      #  end

      private

      attr_reader :provider_entrypoint, :task_id

      def max_number_of_retries 
        if @debug_port_request or $breakpoint
          1
        else
          @failure_attempts
        end
      end

      def dynamically_load_grpc
        self.class.dynamically_load_grpc
      end
      def self.dynamically_load_grpc
        unless @grpc_dynamically_loaded
          require_relative('generic/grpc_helper')
          @grpc_dynamically_loaded = true
        end
      end

      def invoke_action
        Log.info 'Starting generic worker run'
        # spin up the provider gRPC server
        set_grpc_port!(generate_grpc_port)
        Log.debug("gRPC port before generate: #{$dtk_debug_port}")
        if @diff
          set_dtk_debug_port!(generate_debug_port)
          Log.debug("gRPC port bafter generate: #{$dtk_debug_port}")
        else
          #set_dtk_debug_port!($dtk_debug_port)
          Log.info("DEBUG: Different subtasks current port #{$dtk_debug_port}")
	      end
        if @debug_port_request
          debug_response = {}
          debug_response[:dynamic_attributes] = {:dtk_debug_port => $dtk_debug_port}
          debug_response[:success] = "true"
          response_hash =  ResponseHash.create_from_json(debug_response.to_json)
          Log.info("Returning port is:#{$dtk_debug_port}")
          return response_hash.raw_hash_form
        end
        response_hash =
          if ephemeral?
             Log.info("Ports are snet to container: #{@dtk_debug_port} and #{$dtk_debug_port}")
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

      def generate_provider_message(attributes, merge_hash, protocol_version)
        converted_attributes =
          case protocol_version
          when 1, 2
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

      def dtk_debug_port
         $dtk_debug_port #fail("Unexpected that @dtk_debug_port is not set")
      end

      def set_dtk_debug_port!(dtk_debug_port)
        if $dtk_debug_port.nil?
          $dtk_debug_port = dtk_debug_port
        else
          return dtk_debug_port
        end
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
        timeout = $breakpoint ? { :timeout => 1800 } : { :timeout => 240 }
        stub = GrpcHelper.arbiter_service_stub(grpc_address, :this_channel_is_insecure, timeout)

        provider_opts = {:component_name => @component_name,
                         :module_name => @module_name,
                         :breakpoint => $breakpoint,
                         :protocol_version => @protocol_version}
        provider_opts.merge!(:dtk_debug_port => dtk_debug_port, :dtk_debug => $breakpoint) if $breakpoint

        provider_message = generate_provider_message(
                           @attributes,
                           provider_opts,
                           @protocol_version) #provider_message_hash.to_json

        Log.info "Sending a message to the gRPC daemon at #{grpc_address}"
        Log.info "Checking to see if grpc port is open:"
        port_check = port_open?(grpc_host, grpc_port)
        Log.info "#{port_check}"
        # check for debug mode
        # and send response with the debug port set as a dynamic attribute
        #BreakpointHere
        # if $breakpoint
        #   Thread.new(){stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message}
        #   return ResponseHash.create_from_json(debug_response.to_json)
        # end

        grpc_json_response = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        Log.info 'gRPC daemon response received'
        ResponseHash.create_from_json(grpc_json_response)
      end

      PORT_RANGE = 50000..60000
      def generate_grpc_port
        port = nil
        if ephemeral?
          if port = running_container_port?
            return port
          end
        end
        port = find_free_port(PORT_RANGE)
        port
      end

      PORT_RANGE_DEBUG = 30000..40000
      def generate_debug_port
        find_free_port(PORT_RANGE_DEBUG)
      end

      def find_free_port(port_range)
        port = nil
        while port.nil? or port_open?(grpc_host, port) do
          port = rand(port_range)
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