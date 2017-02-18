require 'json'

module DTK::Arbiter
  class Worker::Generic
    class ResponseHash < ::Hash
      def initialize(hash = {})
        replace(hash)
      end
      def self.create_from_json(grpc_json_response)
        new(JSON.parse(grpc_json_response))
      end

      # converts this to a ::Hash object
      def raw_hash_form
        {}.merge(self)
      end

      ERROR_KEY     = 'error'
      ERROR_MSG_KEY = 'error_message'
      ERROR_VALUE   = 'true'

      # opts can have keys
      #   :error_msg
      def self.error(opts = {})
        ret = new(ERROR_KEY => ERROR_VALUE)
        ret.merge!(ERROR_MSG_KEY => opts[:error_msg]) if  opts[:error_msg]
        ret
      end
      def has_error?
        self[ERROR_KEY] == ERROR_VALUE
      end

      def error_message
        if has_error?
          self[ERROR_MSG_KEY] || 'error'
        else
          # This should not be called
          'unknown'
        end
      end

    end
  end
end
