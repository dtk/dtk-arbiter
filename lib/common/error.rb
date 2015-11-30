module Arbiter
  class ErrorFormatter
    class << self

      def action_not_defined(action_name, worker_clazz)
        format_error_message("Action %s for worker %s not defined, aborting action.", action_name, worker_clazz)
      end

      private

      def format_error_message(error_msg, *params)
        sprintf(error_msg, *params)
      end

    end
  end
end