require 'logger'
require 'singleton'
require 'after_do'
require 'fileutils'
require 'json'

module Arbiter
  module Action
    class Log
      include Singleton

      attr_accessor :logger, :error_msgs, :all_msgs

      self.singleton_class.extend AfterDo

      LOG_TO_CONSOLE = false
      LOG_TO_FILE    = '/var/log/action-agent.log'
      LOGS_DIR       = '/var/log/dtk/action-agent'
      # LOG_TO_FILE    = '/Users/haris/test.log'

      def initialize
        # @logger = Logger.new(File.new(LOG_TO_FILE,'w'))
        @all_msgs   =[]
        @error_msgs =[]

        FileUtils.mkdir_p LOGS_DIR unless File.directory?(LOGS_DIR)
      end

      def self.execution_errors()
        self.instance.error_msgs
      end

      def self.debug(msg)
        # self.instance.logger.debug(msg)
        ap "debug: #{msg}" if LOG_TO_CONSOLE
      end

      def self.info(msg)
        # self.instance.logger.info(msg)
        ap "info: #{msg}" if LOG_TO_CONSOLE
      end

      def self.warn(msg, backtrace = nil)
        # self.instance.logger.warn(msg)
        ap "warn: #{msg}" if LOG_TO_CONSOLE
        self.instance.error_msgs <<  { :message => msg, :backtrace => backtrace }
      end

      def self.error(msg, backtrace = nil)
        # self.instance.logger.error(msg)
        ap "error: #{msg}" if LOG_TO_CONSOLE
        self.instance.error_msgs << { :message => msg, :backtrace => backtrace }
      end

      def self.log_results(params_in, results, component_name, action_name, top_task_id, task_id)
        component_dir = File.join(LOGS_DIR, "#{component_name}_#{top_task_id}")
        FileUtils.mkdir_p(component_dir) unless File.directory?(component_dir)

        filename = File.join(component_dir, "#{task_id}_#{action_name}.log")
        File.open(filename, 'w') do |file|
          file.puts('Input data: ')
          file.puts JSON.pretty_generate(params_in)
          file.puts self.instance.all_msgs.join("\n")
          file.puts('Results: ')
          file.puts JSON.pretty_generate(results)
        end
      end


      self.singleton_class.after :debug, :info, :warn, :error do |msg, _backtrace|
        self.instance.all_msgs << msg
      end

    end
  end
end
