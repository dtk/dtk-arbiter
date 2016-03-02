module Arbiter
  module Discovery
    class Worker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end

      def process
        notify_pong
      end

    end
  end
end