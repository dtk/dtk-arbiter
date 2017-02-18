require 'docker'
require 'rufus-scheduler'

module DTK::Arbiter
  class Worker::Generic
    module Docker
      module GarbageCollection
        DOCKER_GC_IMAGE         = 'dtk/docker-gc'
        DOCKER_GC_SCHEDULE      = '1d'
        DOCKER_GC_GRACE_PERIOD  = '86400'
        
        include CommonMixin::Open3
        
        def self.run_garbage_collection
          # enable docker garbace collector schedule
          scheduler = ::Rufus::Scheduler.new
          
          scheduler.every DOCKER_GC_SCHEDULE do
            docker_cli_cmd = "GRACE_PERIOD_SECONDS=#{DOCKER_GC_GRACE_PERIOD} docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /etc:/etc #{DOCKER_GC_IMAGE}"
            docker_run_stdout, docker_run_stderr, exit_status, results = capture3_with_timeout(docker_cli_cmd)
            if exit_status.exitstatus != 0
              Log.error "Something went wrong while running the Docker garbage collector."
              Log.error docker_run_stderr
            end
          end
        end
        
      end
    end
  end
end
