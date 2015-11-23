require 'docker'

require File.expand_path('../../common/worker', __FILE__)

Dir[File.dirname(__FILE__) + '../docker/*.rb'].each { |file| require file }

module Arbiter
  module Docker
    class DockerWorker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)

        @process_pool = []
        @execution_list = @received_message[:execution_list] || []

        #image_id = @received_message[:image_id]
        #@image = Docker::Image.create('fromImage' => 'nginx')
        @image = Docker::Image.create('fromImage' => 'getdtk/trusty-puppet:latest')
      end

      def process()
        if @execution_list.empty?
          notify_of_error("Execution list is not provided or empty, Action Worker has nothing to run!")
          return
        end

        # start commander runnes
        @commander.run()

        results = @commander.results()
        notify(results: results)
      end

    end
  end
end
