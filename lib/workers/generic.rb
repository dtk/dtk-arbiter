require 'grpc'
require 'json'
require 'socket'
require 'timeout'

require File.expand_path('../../common/worker', __FILE__)
require File.expand_path('../../dtkarbiterservice_services_pb', __FILE__)
require File.expand_path('../../docker/commander', __FILE__)

module Arbiter
  module Generic
    class Worker < Common::Worker
      Log.info "Initializing generic worker"

      MODULE_PATH         = "/usr/share/dtk/modules"
      NUMBER_OF_RETRIES   = 5

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
        @component_name_short   = @component_name.split('::')[1]

        @provider_name_internal = "dtk-provider-#{@provider_type}"

        @provider_entrypoint    = "#{MODULE_PATH}/#{@provider_name_internal}/init"
        @pidfile_path           = "/tmp/#{@provider_name_internal}.pid"

        #@provider_data.first['module_name'] = @module_name

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
        grpc_random_port = generate_port
        tries ||= NUMBER_OF_RETRIES
        until (tries -= 1).zero?
          break if start_daemon
          sleep 1
        end
        unless start_daemon
          notify_of_error("Failed to start #{provider_type} gRPC daemon", :missing_params)
          return
        end

        # send a message to the gRPC provider server/daemon
        stub = Dtkarbiterservice::ArbiterProvider::Stub.new("localhost:#{grpc_random_port}", :this_channel_is_insecure)

        # get action attributes and write them JSON serialized to a file
        #action_attributes = @provider_data.first[:action_attributes].to_json
        #action_attributes_file_path  = "/tmp/dtk-#{@module_name}-attributes-#{Time.now.to_i}"
        #File.open(action_attributes_file_path, 'w') { |file| file.write(action_attributes) }
        #@provider_data.first[:action_attributes_file_path] = action_attributes_file_path
        require 'byebug'; debugger
        provider_message_hash = @attributes.merge(:component_name => @component_name_short)
        provider_message = provider_message_hash.to_json

        message = stub.process(Dtkarbiterservice::ProviderMessage.new(message: provider_message)).message
        message = JSON.parse(message)
        stop_daemon

        #::Arbiter::Docker::Worker.new({}, self)

        # if provider returns a message saying that docker execution is required
        # invoke the docker commander
        if message['execution_type'] = 'ephemeral'
          docker_image = nil
          docker_image_tag = @provider_name_internal
          dockerfile = message['dockerfile']
          # this will get appended to the ENTRYPOINT in the image
          # making it the first argument
          # docker_command = action_attributes_file_path

          # commander = Docker::Commander.new(nil,                  # @docker_image
          #                                   docker_command,                  # @docker_command,
          #                                   nil,                  # @puppet_manifest,
          #                                   'ruby',               # @execution_type,
          #                                   dockerfile,
          #                                   @module_name,
          #                                   {},                  # @docker_run_params,
          #                                   nil)                  # @dynamic_attributes

          # commander.run()

          # commander.results()
          Log.info "Building docker image #{docker_image_tag}"
          docker_image = ::Docker::Image.build(dockerfile)
          docker_image.tag('repo' => docker_image_tag, 'force' => true)
          start_daemon_docker(docker_image_tag, grpc_random_port.to_s)
          {}
        else
          response = {:message => message}
          response
        end
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
        # create the container
        container = ::Docker::Container.create(
          'Image' => name,
          'name' => name,
          'ExposedPorts' => { '50051/tcp' => {} },
          'HostConfig' => {
            'PortBindings' => {
              '50051/tcp' => [{ 'HostPort' => port, 'HostIp' => '127.0.0.1' }]
            },
            "Binds" => [
                    "#{MODULE_PATH}:#{MODULE_PATH}"
                ],
          }
        )
        container.start
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

      def generate_port(ip = '127.0.0.1')
        range = 50000..60000
        begin
          port = rand(range)
        end unless port_open?(ip, port)
      end
    end
  end
end