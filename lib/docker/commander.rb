require 'docker'

module Arbiter
  module Docker
    class Commander

      include Common::Open3

      def initialize(docker_image, docker_command, puppet_manifest, execution_type, dockerfile)
        @docker_image = docker_image
        @docker_command = docker_command
        @dockerfile = dockerfile
        @puppet_manifest = puppet_manifest
        @execution_type = execution_type

        unless ::Docker::Image.exist?(docker_image) && !@dockerfile
          Log.info "Getting docker image '#{docker_image}', this may take a while"
          ::Docker::Image.create('fromImage' => docker_image)
        end

         # build required docker image if requested
        if @dockerfile
          Log.info "Building docker image: #{docker_image}"
          image = ::Docker::Image.build(@dockerfile)
          image.tag('repo' => docker_image, 'force' => true)
        end
      end

      def run
        # require 'debugger'; debugger
        docker_container_name = "dtk#{Time.now.to_i}"
        output_dir = "/usr/share/dtk/docker-worker/#{docker_container_name}"
        output_dir_tmp = "#{output_dir}/tmp"
        output_dir_container = "/host_volume"
        output_file = "#{output_dir}/report.yml"
        puppet_modules_dir = '/usr/share/dtk/puppet-modules'


        FileUtils.mkdir_p output_dir_tmp
        # make sure dtkyaml reporter is available to puppet
        FileUtils.ln_sf '/usr/share/dtk/dtk-arbiter/dtkyaml', '/etc/puppet/modules/dtkyaml'
        # write puppet manifest
        File.open("#{output_dir}/manifest.pp", 'w') { |file| file.write(@puppet_manifest) }
        # make sure r8 module is available
        FileUtils.cp_r "/etc/puppet/modules/r8", puppet_modules_dir unless File.exist? "#{puppet_modules_dir}/r8"

        docker_cli_cmd = "docker run --name #{docker_container_name} -v #{output_dir}:#{output_dir_container} -v #{output_dir}/tmp:/tmp" +
                        ((@execution_type.eql? 'puppet') ? " -v #{puppet_modules_dir}:/etc/puppet/modules" : "") + " #{@docker_image} #{@docker_command}"

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

        container = ::Docker::Container.get(docker_container_name)

        @results = Hash.new

        @results[:puppet_report] = docker_puppet_report ||= ''
        @results[:stdout] = docker_run_stdout
        @results[:stderr] = docker_run_stderr
        @results[:status] = exit_status.exitstatus
        @results[:dynamic_attributes] = read_dynamic_attributes(output_dir_tmp)

        # cleanup
        Log.info("Deleting container and doing cleanup")
        container.delete(:force => true)

        # http://unix.stackexchange.com/a/117848
        system("find #{output_dir} -depth -type f -exec shred -n 1 -z -u {} \\;")
        FileUtils.rm_rf(output_dir)
      end

      def results
        @results
      end

    private

      def read_dynamic_attributes(path, identifier = 'dtk_exported_variables')
        full_path = File.join(path, identifier)
        return nil unless File.exists?(full_path)
        Marshal.load(File.read(full_path))
      end

    end
  end
end
