require 'docker'
require 'json'
require 'socket'
require 'timeout'
require 'rufus-scheduler'

module DTK::Arbiter
  class Worker
    class Generic < self
      require_relative('generic/grpc_helper')

      include CommonMixin::Open3

      BASE_DTK_DIR                = '/usr/share/dtk'
      MODULE_DIR                 = "#{BASE_DTK_DIR}/modules"
      SERVICE_INSTANCES_DIR = "#{BASE_DTK_DIR}/service_instances"
      NUMBER_OF_RETRIES           = 5
      DOCKER_GC_IMAGE             = 'dtk/docker-gc'
      DOCKER_GC_SCHEDULE          = '1d'
      DOCKER_GC_GRACE_PERIOD      = '86400'

      # enable docker garbace collector schedule
      scheduler = Rufus::Scheduler.new

      scheduler.every DOCKER_GC_SCHEDULE do
        docker_cli_cmd = "GRACE_PERIOD_SECONDS=#{DOCKER_GC_GRACE_PERIOD} docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /etc:/etc #{DOCKER_GC_IMAGE}"
        docker_run_stdout, docker_run_stderr, exit_status, results = capture3_with_timeout(docker_cli_cmd)
        if exit_status.exitstatus != 0
         Log.error "Something went wrong while running the Docker garbage collector."
         Log.error docker_run_stderr
        end
      end

      #scheduler.join

      def initialize(message_content, listener)
        super(message_content, listener)

        Log.info "Initializing generic worker"

        @protocol_version       = get(:protocol_version) || 0

        @provider_type          = get(:provider_type) || UNKNOWN_PROVIDER
        require 'byebug'; debugger

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
        @container_ip           = inside_docker? ? get_docker_ip : '127.0.0.1'

        # Make sure following is prepared
        FileUtils.mkdir_p(MODULE_DIR, mode: 0755) unless File.directory?(MODULE_DIR)
        # TODO: below should be put in if we want shared space for service instances
        # FileUtils.mkdir_p(SERVICE_INSTANCES_DIR, mode: 0755) unless File.directory?(SERVICE_INSTANCES_DIR)

      end
      private :initialize

      def process
        # we need this to pull our modules
        git_server = Config.git_server

        # pulling modules and preparing environment for changes
        Log.info 'Pulling modules from DTK'
        response = Utils::Git.pull_modules(get(:modules), git_server)

        # run the provider
        provider_run_response = run
        #provider_run_response.merge!(success_response)

        notify(provider_run_response)
      end

      def run
        Log.info 'Starting generic worker run'
        # spin up the provider gRPC server
        grpc_random_port = generate_port
        grpc_address = "#{@container_ip}:#{grpc_random_port}"
         # if docker execution is required
        # spin up the gRPC daemon in a docker container
        if ephemeral?
          docker_image = nil
          docker_image_tag = generate_container_name
          #dockerfile = message['dockerfile']

          Log.info "Building docker image #{docker_image_tag}"
          docker_image = ::Docker::Image.build(@dockerfile)
          docker_image.tag('repo' => docker_image_tag, 'force' => true)
          Log.info "Starting docker container #{docker_image_tag} on port #{grpc_random_port}"
          start_daemon_docker(docker_image_tag, grpc_random_port.to_s)
        else

          tries ||= NUMBER_OF_RETRIES
          until (tries -= 1).zero?
            break if start_daemon
            sleep 1
          end
          unless start_daemon
            notify_of_error("Failed to start #{provider_type} gRPC daemon", :abort_action)
            return
          end
        end

        # send a message to the gRPC provider server/daemon
        stub = GrpcHelper.arbiter_service_stub("#{@container_ip}:#{grpc_random_port}", :this_channel_is_insecure)

        provider_message = generate_provider_message(@attributes, {:component_name => @component_name, :module_name => @module_name}, @protocol_version) #provider_message_hash.to_json

        Log.info 'Sending a message to the gRPC daemon'
        message = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        Log.info 'gRPC daemon response received'
        message = JSON.parse(message)
        # stop the daemon
        ephemeral? ? stop_daemon_docker(docker_image_tag) : stop_daemon

        if message["error"] == "true"
          notify_of_error("#{@provider_type} provider reported an error with message: #{message["error_message"]}", :abort_action)
        end

        # add the gRPC address as a dynamic attribute
        message["dynamic_attributes"] = Hash.new unless message["dynamic_attributes"]
        message["dynamic_attributes"]["grpc_address"] = grpc_address

        message
      end

      private
      
      def start_daemon
        # check if provider daemon is already running
        if File.exist?(@pidfile_path)
          pid = File.read(@pidfile_path).to_i
          return true if (Process.getpgid(pid) rescue false)
        end
        # if not, start it
        begin
          puts 'starting daemon'
          daemon_job = fork do
            Bundler.with_clean_env do
              exec @provider_entrypoint
            end
          end
          sleep 2
          true
        rescue
          false
        end
      end
      
      def stop_daemon
        pid = File.read(@pidfile_path).to_i
        Process.kill("HUP", pid)
      end
      
      def container_running?(name)
        true if ::Docker::Container.get(name) rescue false
      end
      
      def start_daemon_docker(name, port = '50051')
        # remove the container if already running
        stop_daemon_docker(name)
  
        container = ::Docker::Container.create(container_params_hash(name, port))

        container.start
        tries ||= NUMBER_OF_RETRIES
        until (tries -= 1).zero?
          sleep 1
          break if port_open?(@container_ip, port)
        end
        unless port_open?(@container_ip, port)
          notify_of_error("Failed to start #{@provider_type} docker gRPC daemon", :abort_action)
          return
        end
      end

      def container_params_hash(name, port)
        # if running inside docker, use host volume to mount modules instead of internal module path
        module_dir = ENV['HOST_VOLUME'].nil? ? MODULE_DIR : "#{ENV['HOST_VOLUME']}/modules"
        host_config = {
          'PortBindings' => { '50051/tcp' => [{ 'HostPort' => port, 'HostIp' => @container_ip }] },
          'Binds'        => ["#{module_dir}:#{MODULE_DIR}", "#{SERVICE_INSTANCES_DIR}:#{SERVICE_INSTANCES_DIR}"]
        }


        {
          'Image'        => name,
          'name'         => name,
          'Tty'          => true, # needed to run byebug when attach
          'OpenStdin'    => true, # needed to run byebug when attach
          'ExposedPorts' => { '50051/tcp' => {} },
          'HostConfig'   => host_config
        }
      end  

      def stop_daemon_docker(name)
        if container_running?(name)
          begin
            container = ::Docker::Container.get(name)
            container.stop
            container.remove
            true
          rescue
            notify_of_error("Failed to remove existing docker container", :abort_action)
            false
          end
        end
      end

      def port_open?(ip, port, seconds=1)
        Timeout::timeout(seconds) do
          begin
            TCPSocket.new(ip, port).close
            true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            false
          end
        end
      rescue Timeout::Error
        false
      end

      def generate_port(ip = @container_ip)
        container_name = generate_container_name
        if container_running?(container_name)
          container = ::Docker::Container.get(container_name)
          port = container.info["NetworkSettings"]["Ports"]["50051/tcp"].first["HostPort"]
          return port
        else
          range = 50000..60000
          begin
            port = rand(range)
          end unless port_open?(ip, port)
        end
      end

      def ephemeral?
        @execution_type == 'ephemeral_container'
      end

      def get_docker_ip
        route = `/sbin/ip route`
        ip = route.split[2]
        ip
      end

      def inside_docker?
        File.exist?('/.dockerenv')
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

      def generate_container_name
        "#{@service_instance}-#{@component_name}".tr(':','-')
      end
    end
  end
end
