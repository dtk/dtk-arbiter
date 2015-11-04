module Arbiter
  module Common
    class Worker

      def initialize(message, listener)
        @listener = listener
        @received_message = message
        @top_task_id = @received_message[:top_task_id]
        @task_id     = @received_message[:task_id]
        @module_name = @received_message[:module_name]
        @action_name = @received_message[:action_name]
        @request_id  = @received_message[:request_id]
      end

      def process()
        raise "You need to override this method"
      end

      def notify(results)
        @listener.update(results, @request_id)
      end

      def notify_of_error(error_message)
        @listener.update(errors: [error_message], time: Time.now.to_s)
      end

      def to_s
        "#{self.class}"
      end

    end
  end
end