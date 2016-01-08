require 'docker'

require File.expand_path('../../common/worker', __FILE__)
require File.expand_path('../../docker/commander', __FILE__)

Dir[File.dirname(__FILE__) + '../docker/*.rb'].each { |file| require file }

module Arbiter
  module Docker
    class Worker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
        # require 'debugger'; debugger
        @process_pool = []
        @docker_image = @received_message[:docker_image]
        @docker_command = @received_message[:docker_command]
        @dockerfile = @received_message[:dockerfile]
        # can be puppet or bash atm
        @execution_type = @received_message[:execution_type]
        @puppet_manifest = @received_message[:puppet_manifest]
        @commander = Docker::Commander.new(@docker_image, @docker_command, @puppet_manifest, @execution_type, @dockerfile)

        # @image = Docker::Image.create('fromImage' => @docker_image )
      end

      def process()
        # start commander runnes
        @commander.run()

        notify(@commander.results())
      end

    end
  end
end
