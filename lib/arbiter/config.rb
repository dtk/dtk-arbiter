require 'parseconfig'
require 'singleton'
require 'open-uri'

module DTK
  module Arbiter
    class Config

      require 'logger'

      DEFAULT_ARBITER_CFG    = '/etc/dtk/arbiter.cfg'
      DEFAULT_PULSE_INTERVAL = 300
      DEFAULT_CONNECT_RETRIES = 5
      DEFAULT_CONNECT_TIME = 5
      DEFAULT_LOG_LEVEL = Logger::INFO
      DEFAULT_FAILURE_ATTEMPTS = 3
      DEFAULT_FAILURE_SLEEP = 10

      include Singleton

      attr_accessor :stomp_url, :stomp_port, :stomp_username, :stomp_password,
                    :inbox_topic, :outbox_queue, :private_key, :git_server, :pbuilderid, :pulse_interval,
                    :connect_retries, :connect_time, :git_pull_modules, :log_level

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
        # always pull modules unless the config property
        # is explicitly set to 'false'
        @git_pull_modules = retrieve_config('git_pull_modules', config) == 'false' ? false : true
        @pbuilderid = retrieve_config('pbuilderid', config) || collect_pbuilderid
        @pulse_interval = retrieve_config('pulse_interval', config) || DEFAULT_PULSE_INTERVAL
        @connect_retries = retrieve_config('connect_retries', config) || DEFAULT_CONNECT_RETRIES
        @connect_time = retrieve_config('connect_time', config) || DEFAULT_CONNECT_TIME
        @log_level = Logger.const_get(retrieve_config('log_level', config).upcase) rescue DEFAULT_LOG_LEVEL
      end

      def retrieve_config!(key, config)
        value = retrieve_config(key, config)
        raise "Not able to resolve configuration key '#{key}', does #{DEFAULT_ARBITER_CFG} contain that property?" unless value
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
        instance.stomp_port.to_i
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

      def self.pulse_interval
        instance.pulse_interval
      end

      def self.connect_retries
        instance.connect_retries
      end

      def self.connect_time
        instance.connect_time
      end

      def self.git_pull_modules
        instance.git_pull_modules
      end

      def self.log_level
        instance.log_level
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
        begin
          ParseConfig.new(config_path)
        rescue Exception => e
          Log.warn("We are having issues reading '#{config_path}', reason: '#{e.message}'. This is expected behavior on node startup, exiting gracefully.")
          exit(0)
        end
      end

      def config_hash
        {
          stomp_url: @stomp_url,
          stomp_port: @stomp_port,
          stomp_username: @stomp_username,
          stomp_password: @stomp_password,
          inbox_topic: @inbox_topic,
          outbox_queue: @outbox_queue,
          pulse_interval: @pulse_interval
        }
      end

    end
  end
end
