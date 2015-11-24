require 'docker'
require 'open3'

module Arbiter
  module Docker
    Class Commander

      def initialize(docker_image, docker_command)
        unless Docker::Image.exist?(image_id)
          Docker::Image.create('fromImage' => image_id)
        end
        @docker_image = docker_image
        @docker_command = docker_command
      end

      def run
        output_dir = '/usr/share/dtk/docker-worker'
        output_dir_container = "/host_volume"
        output_file = "#{output_dir}/report.yml"
        FileUtils.mkdir_p output_dir
        # make sure dtkyaml reporter is available to puppet
        FileUtils.ln_sf '/usr/share/dtk/dtk-arbiter/dtkyaml' '/etc/puppet/modules/dtkyaml'

        # container = Docker::Container.create(
        #   'Cmd' => [command], 
        #   'Image' => image_id, 
        #   { "Mounts" =>
        #     { "Source" => "/tmp", 
        #       "Destination" => "/tmp", 
        #       "Mode" => "", 
        #       "RW" => "true" }}
        #   tty: true)
        # container.start
        # output = conatiner.logs(stdout: true, tty: true)
        # container.delete
        # output
        docker_cli_cmd = "docker run -v #{output_dir}:#{output_dir_container} #{@docker_image} #{@docker_command}"
        #docker_run_output = `docker run -v #{output_dir}:#{output_dir_container} #{image_id} #{command}`
        @docker_run_stdout = nil
        @docker_run_stderr = nil
        Open3.popen3(docker_cli_cmd) do |stdin, stdout, stderr, wait_thr|
          @docker_run_stdout = stdout.read
          @docker_run_stderr = stderr.read
        end
        begin
          docker_puppet_report = Hash.new
          docker_puppet_report = YAML.load_file(output_file) if File.exist? output_file
        rescue Exception => e
          @error_message = e.message
          @backtrace = e.backtrace
          Log.error(@error_message, @backtrace)
        end
        report[:puppet_report] = docker_puppet_report
        report[:stdout] = @docker_run_stdout
        report[:stderr] = @docker_run_stderr
        report
      end

    end
  end
end
