
# TODO: when add config file for dtk_arbiter make whether these are set configurable
# This must be set before require 'grpc'
#ENV['GRPC_TRACE'] = 'all'
#ENV['GRPC_VERBOSITY'] = 'DEBUG'

# This must be dynamically loaded to avoid bug DTK-2956
require 'grpc'
module DTK::Arbiter
  class Worker::Generic
    module GrpcHelper
      require_relative('grpc_helper/logger')
      require_relative('grpc_helper/dtkarbiterservice_services_pb')

      def self.arbiter_service_stub(*args)
        ::Dtkarbiterservice::ArbiterProvider::Stub.new(*args)
      end

      def self.start_grpc_server
        Thread.start {
          s = GRPC::RpcServer.new
          s.add_http2_port('0.0.0.0:50051', :this_port_is_insecure)
          s.handle(ArbiterGRPCServer)
          s.run_till_terminated
        }
      end

    end
  end

  class ArbiterGRPCServer < Dtkarbiterservice::ArbiterProvider::Service
    # say_hello implements the SayHello rpc method.
    def process(hello_req, _unused_call)
      response = {:ok => true}
      Dtkarbiterservice::ArbiterMessage.new(message: response.to_json)
    end
  end
end
