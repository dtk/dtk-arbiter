require 'parseconfig'
require 'singleton'
require 'open-uri'
require 'timeout'

module Arbiter
  module Utils
    class Config

      DEFAULT_ARBITER_CFG = '/etc/dtk/arbiter.cfg'

      include Singleton

      attr_accessor :stomp_url, :stomp_port, :stomp_username, :stomp_password, :inbox_topic, :outbox_queue, :private_key, :git_server, :pbuilderid

      def initialize
        config = load_arbiter_configuration

        @stomp_url  = ENV['STOMP_URL'] || retrieve_config!('stomp_url', config)
        @stomp_port = ENV['STOMP_PORT'] || retrieve_config!('stomp_port', config)
        @stomp_username = ENV['STOMP_USERNAME'] || retrieve_config!('stomp_username', config)
        @stomp_password = ENV['STOMP_PASSWORD'] || retrieve_config!('stomp_password', config)
        @inbox_topic = ENV['INBOX_TOPIC'] || retrieve_config!('arbiter_topic', config)
        @outbox_queue = ENV['OUTBOX_queue'] || retrieve_config!('arbiter_queue', config)
        @private_key = retrieve_config!('private_key', config)
        @git_server = retrieve_config!('git_server', config)
        @pbuilderid = retrieve_config('pbuilderid', config) || collect_pbuilderid
      end

      def retrieve_config!(key, config)
        value = retrieve_config(key, config)
        raise "Not able to resolve configuration key '#{key}', does #{DEFAULT_MC_FILE} contain that property?" unless value
        value
      end

      def retrieve_config(key, config)
        value = config[key]
        (value && !value.empty?) ? value : nil
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

      def self.outbox_queue
        instance.outbox_queue
      end

      def self.private_key
        instance.private_key
      end

      def self.git_server
        instance.git_server
      end

      def self.pbuilderid
        instance.pbuilderid
      end

    private

      def collect_pbuilderid
        ret = nil
        begin
          addr = "169.254.169.254"
          wait_sec = 2
          Timeout::timeout(wait_sec) {open("http://#{addr}:80/")}
          ret = OpenURI.open_uri("http://#{addr}/2008-02-01/meta-data/instance-id").read
        rescue Timeout::Error
        rescue
          #TODO: unexpected; write to log what error is
        end
        ret
      end

      def load_arbiter_configuration(config_path = DEFAULT_ARBITER_CFG)
        ParseConfig.new(config_path)
      end

      def config_hash
        {
          stomp_url: @stomp_url,
          stomp_port: @stomp_port,
          stomp_username: @stomp_username,
          stomp_password: @stomp_password,
          inbox_topic: @inbox_topic,
          outbox_queue: @outbox_queue,
        }
      end

    end
  end
end