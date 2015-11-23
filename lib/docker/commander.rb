require 'docker'

module Arbiter
  module Docker
    Class Commander

      def check_image(image_id)
        unless Docker::Image.exist?(image_id)
          Docker::Image.create('fromImage' => 'getdtk/trusty-puppet:latest')
        end
      end

      def run(image_id, command)
        output_dir = "/usr/share/dtk/docker-worker"
        output_dir_container = "/host_volume"
        output_file = "#{output_dir}/report.yml"
        FileUtils.mkdir_p output_dir
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
        docker_run_output = `docker run -v #{output_dir}:#{output_dir_container} #{image_id} #{command}`
        report = YAML.load_file(output_file)
        report.inspect
      end

    end
  end
end

#{"State"=>{"Running"=>false, "Pid"=>0, "ExitCode"=>0, "StartedAt"=>"0001-01-01T00:00:00Z", "Ghost"=>false}
{"Mounts" =>{"Source" => "/tmp", "Destination" => "/tmp", "Mode" => "", "RW" => "true" }}


{}    "Mounts": [
        {
            "Source": "/tmp",
            "Destination": "/tmp",
            "Mode": "",
            "RW": true
        }
    ],