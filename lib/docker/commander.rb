require 'docker'
require 'open3'

module Arbiter
  module Docker
    class Commander

      def initialize(docker_image, docker_command, puppet_manifest, execution_type, dockerfile)
        @docker_image = docker_image
        @docker_command = docker_command
        @dockerfile = dockerfile
        @puppet_manifest = puppet_manifest
        @execution_type = execution_type
        unless ::Docker::Image.exist?(docker_image) && !@dockerfile
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
#require 'debugger'; debugger
        docker_container_name = "dtk#{Time.now.to_i}"
        output_dir = "/usr/share/dtk/docker-worker/#{docker_container_name}"
        output_dir_container = "/host_volume"
        output_file = "#{output_dir}/report.yml"
        puppet_modules_dir = '/usr/share/dtk/puppet-modules'
        FileUtils.mkdir_p "#{output_dir}/tmp"
        # make sure dtkyaml reporter is available to puppet
        FileUtils.ln_sf '/usr/share/dtk/dtk-arbiter/dtkyaml', '/etc/puppet/modules/dtkyaml'
        # write puppet manifest
        File.open("#{output_dir}/manifest.pp", 'w') { |file| file.write(@puppet_manifest) }
        # make sure r8 module is available
        FileUtils.cp_r "/etc/puppet/modules/r8", puppet_modules_dir unless File.exist? "#{puppet_modules_dir}/r8"

        docker_cli_cmd = "docker run --name #{docker_container_name} -v #{output_dir}:#{output_dir_container} -v #{output_dir}/tmp:/tmp" + 
                        ((@execution_type.eql? 'puppet') ? " -v #{puppet_modules_dir}:/etc/puppet/modules" : "") + " #{@docker_image} #{@docker_command}"
        #docker_run_output = `docker run -v #{output_dir}:#{output_dir_container} #{image_id} #{command}`
        @docker_run_stdout = nil
        @docker_run_stderr = nil
        @exit_status = nil
        Log.info "Starting Docker container..."
        Open3.popen3(docker_cli_cmd) do |stdin, stdout, stderr, wait_thr|
          @docker_run_stdout = stdout.read
          @docker_run_stderr = stderr.read
          @exit_status = wait_thr.value.to_i
        end
        if @execution_type.eql? 'puppet'
          begin
            docker_puppet_report = Hash.new
            docker_puppet_report = YAML.load_file(output_file) if File.exist? output_file
          rescue Exception => e
            @error_message = e.message
            @backtrace = e.backtrace
            Log.error(@error_message, @backtrace)
          end
        end

        container = ::Docker::Container.get(docker_container_name)

        @results = Hash.new
        @results[:puppet_report] = docker_puppet_report ||= ''
        @results[:stdout] = @docker_run_stdout
        @results[:stderr] = @docker_run_stderr
        @results[:status] = @exit_status

        # cleanup
        Log.info("Deleting container and doing cleanup")
        container.delete(:force => true)
        # http://unix.stackexchange.com/a/117848
        #system("find #{output_dir} -depth -type f -exec shred -v -n 1 -z -u {} \\;")
        #system("rm -rf #{output_dir}")
      end

      def results
        @results
      end

    end
  end
end