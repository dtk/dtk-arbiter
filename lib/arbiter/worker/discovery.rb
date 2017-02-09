module DTK
  class Arbiter::Worker
    class Discovery < self
      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end

      def process
        notify_heartbeat
      end

    end
  end
end
