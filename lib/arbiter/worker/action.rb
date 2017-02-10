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
        @execution_list = @received_message[:execution_list] || []
        @commander = Commander.new(@execution_list)
      end
      private :initialize

      def process
        if @execution_list.empty?
          notify_of_error("Execution list is not provided or empty, Action Worker has nothing to run!", :missing_params)
          return
        end

        # start commander runs
        @commander.run
        results = @commander.results


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
