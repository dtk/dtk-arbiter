module DTK::Arbiter
  class Worker
    class Action < self
      attr_reader :process_pool
      require_relative('action/command')
      require_relative('action/position')
      require_relative('action/commander')

      BASE_DTK_DIR          = '/usr/share/dtk'
      MODULE_DIR            = "#{BASE_DTK_DIR}/modules"

      def initialize(message_content, listener)
        super(message_content, listener)

        @process_pool = []
        @execution_list = @received_message[:execution_list] || []
        @service_name = @received_message[:service_name]
        @module_name_base = @received_message[:module_name].split(':')[1]

        # replace references to obsolete module paths in commands
        unadjusted_path = "#{MODULE_DIR}/#{@module_name_base}/"
        adjusted_path = "#{MODULE_DIR}/#{@service_name}/#{@module_name_base}/"
        @execution_list.each do |e|
          e[:command].gsub!(unadjusted_path, adjusted_path)
        end

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
