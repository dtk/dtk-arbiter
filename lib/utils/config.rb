require 'parseconfig'
require 'singleton'

module Arbiter
  module Utils
    class Config

      DEFAULT_MC_FILE = '/etc/mcollective/server.cfg'

      include Singleton

      attr_accessor :stomp_url, :stomp_port, :stomp_username, :stomp_password, :inbox_topic, :outbox_topic

      def initialize
        config = load_mcollective_configuration

        @stomp_url  = ENV['STOMP_URL'] || config['plugin.stomp.host']
        @stomp_port = ENV['STOMP_PORT'] || config['plugin.stomp.port']
        @stomp_username = ENV['STOMP_USERNAME'] || config['plugin.stomp.user']
        @stomp_password = ENV['STOMP_PASSWORD'] || config['plugin.stomp.password']
        @inbox_topic = ENV['INBOX_TOPIC'] || 'mcollective.dtk'
        @outbox_topic = ENV['OUTBOX_TOPIC'] || 'mcollective.dtk.reply'
      end

      def self.full_url
        "stomp://#{stomp_url}:#{stomp_port}"
      end

      def self.stomp_url
        instance.stomp_url
      end

      def self.stomp_port
        instance.stomp_port
      end

      def self.stomp_username
        instance.stomp_username
      end

      def self.stomp_password
        instance.stomp_password
      end

      def self.inbox_topic
        instance.inbox_topic
      end

      def self.outbox_topic
        instance.outbox_topic
      end

    private

      def load_mcollective_configuration(config_path = DEFAULT_MC_FILE)
        config = ParseConfig.new(config_path)
      end

    end
  end
end