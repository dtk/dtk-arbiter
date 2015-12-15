require File.expand_path('../../action/commander', __FILE__)

Dir[File.dirname(__FILE__) + '../action/*.rb'].each { |file| require file }

module Arbiter
  module Action
    class Worker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)

        @process_pool = []
        @execution_list = @received_message[:execution_list] || []
        @commander = Action::Commander.new(@execution_list)
      end

      def process()
        if @execution_list.empty?
          notify_of_error("Execution list is not provided or empty, Action Worker has nothing to run!", :missing_params)
          return
        end

        # start commander runs
        @commander.run()

        notify(@commander.results())
      end

    end
  end
end