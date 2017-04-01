
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

    end
  end
end
