module DTK::Arbiter
  module Worker::Generic::GrpcHelper
    class Logger < ::DTK::Arbiter::Log
      def self.info(msg)
        super("grpc: #{msg}")
      end
      def self.debug(msg)
        super("grpc: #{msg}")
      end
      def self.warn(msg)
        super("grpc: #{msg}")
      end
    end
  end
end

# This indicates that DTKLogger used to log grpc messages
module GRPC
  def self.logger
    ::DTK::Arbiter::Worker::Generic::GrpcHelper::Logger
  end
end
