module Arbiter
  module Discovery
    class Worker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end

      def process()
        Log.info("Processing ping from the server ...")
        notify({ :resut => 'pong' })
      end

    end
  end
end