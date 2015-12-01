require 'docker'

require File.expand_path('../../common/worker', __FILE__)
require File.expand_path('../../docker/commander', __FILE__)

Dir[File.dirname(__FILE__) + '../docker/*.rb'].each { |file| require file }

module Arbiter
  module Docker
    class DockerWorker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
require 'debugger'; debugger
        @process_pool = []
        @execution_list = @received_message[:execution_list] || []
        @docker_image = @received_message[:docker_image]
        @docker_command = @received_message[:docker_command]
        @commander = Docker::Commander.new(@docker_image, @docker_command)

        #@image = Docker::Image.create('fromImage' => @docker_image )
      end

      def process()
#        if @execution_list.empty?
#          notify_of_error("Execution list is not provided or empty, Docker Worker has nothing to run!")
#          return
#        end

        # start commander runnes
        @commander.run()

        notify(@commander.results())
      end

    end
  end
end
