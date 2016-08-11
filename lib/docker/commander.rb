require 'docker'
require 'digest/sha1'

module Arbiter
  module Docker
    class Commander

      include Common::Open3

      NUMBER_OF_RETRIES = 5
      WAIT_TIME = 5

      def initialize(docker_image, docker_command, puppet_manifest, execution_type, dockerfile, module_name, docker_run_params, dynamic_attributes)
        @docker_image = docker_image
        @docker_command = docker_command
        @dockerfile = dockerfile
        @puppet_manifest = puppet_manifest
        @execution_type = execution_type
        @docker_image_tag = Digest::SHA1.hexdigest @dockerfile if @dockerfile
        @docker_image_final = @docker_image_tag || @docker_image
        @module_name = module_name
        @docker_run_params = docker_run_params
        @dynamic_attributes = dynamic_attributes

        # make sure we can connect to Docker daemon
        docker_conn_retries = NUMBER_OF_RETRIES

        begin
          raise ActionAbort, "Arbiter not able to connect to Docker daemon." if docker_conn_retries == 0
          images = ::Docker::Image.all
        rescue Excon::Errors::SocketError => e
          Log.info("Failed to connect to Docker daemon, retrying.")
          sleep WAIT_TIME
          docker_conn_retries -= 1
          retry
        end

        unless @dockerfile
          Log.info "Getting docker image '#{docker_image}', this may take a while"
          ::Docker::Image.create('fromImage' => docker_image)
        end
      end

      def run
        # TODO: DTK-2553: dario, put in very fast workaround; we should do away with using name and instead get container using its id
#        docker_container_name = @docker_run_params[:name] || "dtk#{Time.now.to_i}"
        docker_container_name = "dtk#{Time.now.to_i}"
        output_dir = "/usr/share/dtk/docker-worker/#{docker_container_name}"
        output_dir_tmp = "#{output_dir}/tmp"
        output_dir_container = "/host_volume"
        output_file = "#{output_dir}/report.yml"
        puppet_modules_dir = '/usr/share/dtk/puppet-modules'
        ## get the module that invoked the docke action
        # remove namespace
        @module_name_short = @module_name.split(':')[1]
        module_absolute_location = "#{puppet_modules_dir}/#{@module_name_short}"

        FileUtils.mkdir_p output_dir_tmp
        # make sure dtkyaml reporter is available to puppet
        FileUtils.ln_sf '/usr/share/dtk/dtk-arbiter/dtkyaml', '/etc/puppet/modules/dtkyaml'
        # write puppet manifest
        File.open("#{output_dir}/manifest.pp", 'w') { |file| file.write(@puppet_manifest) }
        # make sure r8 module is available
        FileUtils.cp_r "/etc/puppet/modules/r8", puppet_modules_dir unless File.exist? "#{puppet_modules_dir}/r8"

         # build required docker image if requested
        if @dockerfile
          # generate the dockerfile in the module root
          # use a name with a timestamp to avoid overriting any possible existing Dockerfiles
          dockerfile_name = "Dockerfile.dtk#{Time.now.to_i}"
          dockerfile_location = "#{module_absolute_location}/#{dockerfile_name}"
          Log.info("Generating Dockerfile: #{dockerfile_location}")
          File.open(dockerfile_location, 'w') { |file| file.write(@dockerfile) }
          Log.info "Building docker image: #{@docker_image_tag}"
          # image = ::Docker::Image.build(@dockerfile)
          image = ::Docker::Image.build_from_dir(module_absolute_location, { 'dockerfile' => dockerfile_name })
          image.tag('repo' => @docker_image_tag, 'force' => true)
          # delete the temporary Dockerfile
          #FileUtils.rm(dockerfile_location)
        end

        docker_cli_cmd = "docker run --name #{docker_container_name} -v #{output_dir}:#{output_dir_container} -v #{output_dir}/tmp:/tmp" +
                        ((@execution_type.eql? 'puppet') ? " -v #{puppet_modules_dir}:/etc/puppet/modules" : "") + 
                        " -v #{puppet_modules_dir}:#{puppet_modules_dir}" + 
                        get_cli_args(@docker_run_params, module_absolute_location) +
                        " #{@docker_image_final} #{@docker_command}"
        Log.info "Starting Docker container..."

        docker_run_stdout, docker_run_stderr, exit_status, results = capture3_with_timeout(docker_cli_cmd)

        if @execution_type.eql? 'puppet'
          begin
            docker_puppet_report = Hash.new
            docker_puppet_report = YAML.load_file(output_file) if File.exist? output_file
          rescue Exception => e
            Log.error("Docker (puppet) report error: #{e.message}", e.backtrace)
          end
        end

        container = ::Docker::Container.get(docker_container_name) unless @docker_run_params[:rm]

        @results = Hash.new
        dyn_attr_data = read_dynamic_attributes(output_dir_tmp) || read_dynamic_attributes(output_dir_tmp, 'dtk_exported_variables_json', 'json')

        @results[:puppet_report] = docker_puppet_report ||= ''
        @results[:stdout] = docker_run_stdout
        @results[:stderr] = docker_run_stderr
        @results[:status] = exit_status.exitstatus
        @results[:dynamic_attributes] = process_dynamic_attributes(dyn_attr_data, @dynamic_attributes) 

        # cleanup
#        Log.info("Deleting container and doing cleanup")
#        container.delete(:force => true)

        # http://unix.stackexchange.com/a/117848
        system("find #{output_dir} -depth -type f -exec shred -n 1 -z -u {} \\;")
        FileUtils.rm_rf(output_dir)
      end

      def results
        @results
      end

    private

      def get_cli_args (docker_run_params, module_location)
        cli_args = ' '
        # add env vars
        cli_args += docker_run_params[:environment].map{|k,v| "-e #{k}=#{v}"}.join(' ') + ' ' if docker_run_params[:environment]
        # add entrypoint
        cli_args += " --entrypoint #{module_location}/#{docker_run_params[:entrypoint]} "
        # add volumes
        cli_args += docker_run_params[:volumes].map{|a| "-v #{module_location}/#{a}"}.join(' ') + ' ' if docker_run_params[:volumes]
        # set privileged
        cli_args += ' --privileged ' if docker_run_params[:privileged]
        # set rm
        cli_args += ' --rm ' if docker_run_params[:rm]
        # set name
        # cli_args += "--name #{docker_run_params[:name]} " if docker_run_params[:name]

        cli_args
      end

      def read_dynamic_attributes(path, identifier = 'dtk_exported_variables', format = 'marshal')
        full_path = File.join(path, identifier)
        return nil unless File.exists?(full_path)
        case format
        when 'marshal'
          Marshal.load(File.read(full_path))
        when 'json'
          json_dump = JSON.parse(File.read(full_path))
          @module_name_short.nil? ? json_dump : {@module_name_short => json_dump}
        else
          return nil
        end
      end

      def process_dynamic_attributes(dyn_attr_data, dyn_attr_info)
        final_array = []

        dyn_attr_info.each do |ref_obj|
          cmp_ref      = ref_obj[:component_ref].split('::')[0]
          cmp_ref_name = ref_obj[:name]
          cmp_ref_id   = ref_obj[:id]

          cmp_file = dyn_attr_data[cmp_ref]
          cmp_ref_val = cmp_file[cmp_ref_name]

          final_array << {:attribute_id => cmp_ref_id, :attribute_val => cmp_ref_val}
        end
        {:dynamic_attributes => final_array}
      end

    end
  end
end
