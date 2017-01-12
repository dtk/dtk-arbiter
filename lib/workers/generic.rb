require 'grpc'
require 'json'
require 'socket'
require 'timeout'
require 'rufus-scheduler'

require File.expand_path('../../common/worker', __FILE__)
require File.expand_path('../../dtkarbiterservice_services_pb', __FILE__)
require File.expand_path('../../docker/commander', __FILE__)

module Arbiter
  module Generic
    class Worker < Common::Worker
      Log.info "Initializing generic worker"

      include Common::Open3

      MODULE_PATH            = "/usr/share/dtk/modules"
      NUMBER_OF_RETRIES      = 5
      DOCKER_GC_IMAGE        = 'dtk/docker-gc'
      DOCKER_GC_SCHEDULE     = '1d'
      DOCKER_GC_GRACE_PERIOD = '86400'

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

        @provider_type          = get(:provider_type) || UNKNOWN_PROVIDER
        #@provider_data    = get(:provider_data) || NO_PROVIDER_DATA
        @attributes             = get(:attributes)
        @provider_attributes    = @attributes[:provider]
        @instance_attributes    = @attributes[:instance]
        #@version_context     = get(:version_context)
        @modules = get(:modules)
        @component_name         = get(:component_name)
        # i.e. remove namespace
        @module_name = @component_name.split(':')[1]

        @execution_type = get(:execution_environment)[:type]
        @dockerfile = get(:execution_environment)[:docker_file]

        @provider_name_internal = "#{@provider_type}-provider"

        @provider_entrypoint    = "#{MODULE_PATH}/#{@provider_name_internal}/init"
        @pidfile_path           = "/tmp/#{@provider_name_internal}.pid"

        @container_ip = inside_docker? ? get_docker_ip : '127.0.0.1'

        # Make sure following is prepared
        FileUtils.mkdir_p(MODULE_PATH, mode: 0755) unless File.directory?(MODULE_PATH)
      end

      def process()
        # we need this to pull our modules
        git_server = Utils::Config.git_server

        # pulling modules and preparing environment for changes
        response = Utils::Git.pull_modules(get(:modules), git_server)

        # run the provider
        provider_run_response = run()
        #provider_run_response.merge!(success_response)

        notify(provider_run_response)
      end

      def run()
        # spin up the provider gRPC server
        grpc_random_port = '50051' #generate_port
         # if docker execution is required
        # spin up the gRPC daemon in a docker container
        if ephemeral?
          docker_image = nil
          docker_image_tag = @provider_name_internal
          #dockerfile = message['dockerfile']

          Log.info "Building docker image #{docker_image_tag}"
          docker_image = ::Docker::Image.build(@dockerfile)
          docker_image.tag('repo' => docker_image_tag, 'force' => true)
          start_daemon_docker(docker_image_tag, grpc_random_port.to_s)
        else

          tries ||= NUMBER_OF_RETRIES
          until (tries -= 1).zero?
            break if start_daemon
            sleep 1
          end
          unless start_daemon
            notify_of_error("Failed to start #{provider_type} gRPC daemon", :missing_params)
            return
          end
        end

        # send a message to the gRPC provider server/daemon
        stub = Dtkarbiterservice::ArbiterProvider::Stub.new("#{@container_ip}:#{grpc_random_port}", :this_channel_is_insecure)
        # get action attributes and write them JSON serialized to a file
        #action_attributes = @provider_data.first[:action_attributes].to_json
        #action_attributes_file_path  = "/tmp/dtk-#{@module_name}-attributes-#{Time.now.to_i}"
        #File.open(action_attributes_file_path, 'w') { |file| file.write(action_attributes) }
        #@provider_data.first[:action_attributes_file_path] = action_attributes_file_path

        provider_message_hash = @attributes.merge(:component_name => @component_name, :module_name => @module_name)
        provider_message = provider_message_hash.to_json

        message = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        message = JSON.parse(message)
        # stop the daemon
        ephemeral? ? stop_daemon_docker(docker_image_tag) : stop_daemon

        message
        #response

      end

  private

      def start_daemon()
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

      def stop_daemon()
        pid = File.read(@pidfile_path).to_i
        Process.kill("HUP", pid)
      end

      def container_running?(name)
        true if ::Docker::Container.get(name) rescue false
      end

      def start_daemon_docker(name, port = '50051')
        # remove the container if already running
        stop_daemon_docker(name)
        # if running inside docker, use host volume to mount modules instead of internal module path
        module_path = ENV['HOST_VOLUME'].nil? ? MODULE_PATH : "#{ENV['HOST_VOLUME']}/modules"
        # create the container
        container = ::Docker::Container.create(
          'Image' => name,
          'name' => name,
          'ExposedPorts' => { '50051/tcp' => {} },
          'HostConfig' => {
            'PortBindings' => {
              '50051/tcp' => [{ 'HostPort' => port, 'HostIp' => @container_ip }]
            },
            "Binds" => [
                "#{module_path}:#{MODULE_PATH}"
              ],
          }
        )
        container.start
        tries ||= NUMBER_OF_RETRIES
        until (tries -= 1).zero?
          sleep 1
          break if port_open?(@container_ip, port)
        end
        unless port_open?(@container_ip, port)
          notify_of_error("Failed to start #{@provider_type} docker gRPC daemon", :missing_params)
          return
        end
      end

      def stop_daemon_docker(name)
        if container_running?(name)
          begin
            container = ::Docker::Container.get(name)
            container.stop
            container.remove
            true
          rescue
            notify_of_error("Failed to remove existing docker container", :missing_params)
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

      def generate_port(ip = CONTAINER_IP)
        range = 50000..60000
        begin
          port = rand(range)
        end unless port_open?(ip, port)
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
    end
  end
end
