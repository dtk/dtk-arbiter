module DTK::Arbiter
  class Worker::Generic
    module GrpcHelper
      require_relative('grpc_helper/dtkarbiterservice_services_pb')

      def self.arbiter_service_stub(*args)
        ::Dtkarbiterservice::ArbiterProvider::Stub.new(*args)
      end

    end
  end
end
