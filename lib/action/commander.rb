require File.expand_path('../command', __FILE__)
require File.expand_path('../position', __FILE__)


module Arbiter
  module Action
    class Commander

      PARALLEL_EXECUTION = ENV['ARBITER_ACTION_PARALLEL_EXECUTION'] || false

      def initialize(execution_list)
        @command_tasks  = execution_list.collect do |command|
          if ('file'.eql?(command[:type]))
            Position.new(command)
          else
            Command.new(command)
          end
        end
      end

      def run
        if PARALLEL_EXECUTION
          parallel_run()
        else
          sequential_run()
        end
      end

      def sequential_run
        @command_tasks.each do |command_task|

          if command_task.callback_pending? && !command_task.run_condition_task
            Log.info("Skipping command task #{command_task}, conditions have not been met")
            next
          end

          command_task.start_task
          loop do
            if command_task.exited?
              Log.debug("Command '#{command_task}' finished, with status #{command_task.exitstatus}")

              # exit if there is an error
              return nil if (command_task.exitstatus.to_i > 0)

              break
            end

            sleep(1)
          end

        end
      end

      def parallel_run
        @command_tasks.each do |command_task|
          if command_task.callback_pending? && !command_task.run_condition_task
            Log.info("Skipping command task #{command_task}, conditions have not been met")
            next
          end
          command_task.start_task
        end

        loop do
          all_finished = true
          sleep(1)

          # we check status of all tasks
          @command_tasks.each do |command_task|
            # is task finished
            if command_task.exited?
              Log.debug("Command '#{command_task}' finished, with status #{command_task.exitstatus}")
            else
              # we are not ready yet, some tasks need to finish
              all_finished = false
            end
          end

          break if all_finished
        end
      end

      def results
        res = @command_tasks.collect do |command_task|
          next unless command_task.started?
          {
            :status      => command_task.exitstatus,
            :stdout      => command_task.out,
            :stderr      => command_task.err,
            :description => command_task.to_s,
            :backtrace   => command_task.backtrace
          }
        end

        res.compact
      end

    private

      def self.clear_environment_variables(env_vars_hash)
        return unless env_vars_hash
        env_vars_hash.keys.each do |k|
          ENV.delete(k)
          Log.debug("Environment variable cleared (#{k})")
        end
      end

      ##
      # Sets environmental variables
      def self.set_environment_variables(env_vars_hash)
        return unless env_vars_hash
        env_vars_hash.each do |k, v|
          ENV[k] = v.to_s.strip
          Log.debug("Environment variable set (#{k}: #{v})")
        end
      end

    end

  end
end