
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
      require_relative('grpc_helper/arbitergrpc_services_pb')
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

  class ArbiterGRPCServer < Dtkarbiterservice::ArbiterRemoteCall::Service
    def process(message, _unused_call)
      message_hash = JSON.parse(message.message)
      attributes = message_hash["attributes"]
      component_name = message_hash["component_name"]
      module_name = component_name.split("::").first
      attributes_converted = {}
      attributes.each do |k,v|
        datatype = (v.class == Hash) ? 'json' : 'string'
        attributes_converted.merge!({k.to_s => {:value => v, :datatype=>datatype, :hidden=>false}})
      end
      message_hardcoded = {:agent=>"generic_worker", 
                 :method=>"run", 
                 :remote_call=>true,
                 :protocol_version=>1,
                 :provider_type=>"ruby",
                 :service_instance=>module_name,
                 :component=>{:type=>component_name, :version=>"0.9.5", :title=>"node", :namespace=>module_name, :module_name=>module_name}, 
                 :attributes=>
                   {:provider=>{"entrypoint"=>{:value=>"bin/object__converge.rb", :datatype=>"string", :hidden=>false}}, 
                    :instance=>{"system.service_instance_name"=>{:value=>module_name, :datatype=>"string", :hidden=>false},"instance_type"=>{:value=>nil, :datatype=>"string", :hidden=>false}}}, 
                    :execution_environment=>{:type=>"bash"}, :pbuilderid=>"docker-executor"}
      message_hardcoded[:attributes][:instance].merge!(attributes_converted)
      generic_worker = ::DTK::Arbiter::Worker::Generic.new(message_hardcoded, nil)
      response = generic_worker.process
      Dtkarbiterservice::ArbiterResponseMessage.new(message: response.to_json)
    end
  end
end
