module Arbiter
  module Common
    class Worker

      def initialize(message, listener)
        @listener = listener
        @received_message = message
        @agent_name  = @received_message[:agent]
        @top_task_id = @received_message[:top_task_id]
        @task_id     = @received_message[:task_id]
        @module_name = @received_message[:module_name]
        @action_name = @received_message[:method] ? @received_message[:method].to_sym : nil
        @request_id  = @received_message[:request_id]
        @service_name = @received_message[:service_name]
      end

      def process()
        raise "You need to override this method"
      end

      def notify(results, is_error_results = false)
        @listener.update(results, @request_id, is_error_results)
        Log.log_results(@received_message, results, @agent_name, @action_name, @top_task_id, @task_id, self.class.to_s)
      end

      def notify_of_error(error_message, error_type = :arbiter_error)
        @listener.update([{ error: error_message, time: Time.now.to_s, type: error_type }], @request_id, true)
      end

      def notify_of_error_results(results)
        notify(results, true)
      end

      def to_s
        "#{self.class}"
      end

      def action_name
        @action_name ? @action_name.downcase.to_sym : nil
      end

    protected

      def success_response(extended_response = {})
        { :status => :succeeded }.merge!(extended_response)
      end

      def get(identifier)
        instance_variable_get("@#{identifier}") || @received_message[identifier.to_sym]
      end

      def top_task_id
        get(:top_task_id)
      end

      def task_id
        get(:task_id)
      end

      def check_required!(*instance_variables)
        errors = []
        [*instance_variables].each do |iv|
          errors << "Missing required parameter '#{iv}'" unless (instance_variable_get("@#{iv}") || @received_message[iv])
        end

        raise Arbiter::MissingParams, errors.join(', ') unless errors.empty?
      end

    end
  end
end