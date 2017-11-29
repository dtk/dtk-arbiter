module DTK::Arbiter
  class Worker
    class Action < self
      attr_reader :process_pool
      require_relative('action/command')
      require_relative('action/position')
      require_relative('action/commander')

      def initialize(message_content, listener)
        super(message_content, listener)

        @process_pool = []
        @failure_attempts = get(:failure_attempts) || Config::DEFAULT_FAILURE_ATTEMPTS
        @failure_sleep    = get(:failure_sleep) || Config::DEFAULT_FAILURE_SLEEP
        @execution_list = @received_message[:execution_list] || []
        @commander = Commander.new(@execution_list)
      end
      private :initialize

      def process
        # we need this to pull our modules
        git_server = Config.git_server

        # pulling modules and preparing environment for changes
        Log.info 'Pulling modules from DTK'
        response = Utils::Git.pull_modules(get(:modules), git_server)

        if @execution_list.empty?
          notify_of_error("Execution list is not provided or empty, Action Worker has nothing to run!", :missing_params)
          return
        end

        tries = @failure_attempts 
        sleep_between_retries = @failure_sleep
        # start commander runs
        begin
          @commander.run
          results = @commander.results
          raise ActionAbort, "Not able to execute bash action, exitstatus: #{exitstatus}, error: #{stderr}" if are_there_errors_in_results?(results)

        rescue Exception => e
          if (tries -= 1) > 0
            Log.warn("Re-trying bash action because of error: #{e.message}, retries left: #{tries}")
            sleep(sleep_between_retries)
            retry
          end
          Log.warn("No retries left, sending error notification.")
        end

        if are_there_errors_in_results?(results)
          notify_of_error_results(results)
        else
          notify(results)
        end
      end

    private

      ##
      # Simple check to see if there non zero status codes
      #

      def are_there_errors_in_results?(results)
        error_outputs = results.select { |a| a[:status] != 0 }
        !error_outputs.empty?
      end

      # def are_there_errors_in_results?(results)
      #   error_outputs = results.select { |a| a[:status] != 0 }.uniq
      #   return nil if error_outputs.empty?

      #   results.collect { |a| "Command '#{a[:description]}' failed with status code #{a[:status]}, output: #{a[:stderr]}"}.join(', ')
      # end

    end
  end
end
