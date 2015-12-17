require 'logger'
require 'singleton'
require 'after_do'
require 'fileutils'
require 'json'
require 'ap'

module Arbiter
  class Log
    include Singleton

    attr_accessor :logger, :error_msgs, :all_msgs

    self.singleton_class.extend AfterDo

    LOG_TO_CONSOLE = false
    LOGS_DIR       = '/var/log/dtk/arbiter-messages'

    def initialize
      @logger = Logger.new(STDOUT)
      @all_msgs   =[]
      @error_msgs =[]

      FileUtils.mkdir_p LOGS_DIR unless File.directory?(LOGS_DIR)
    end

    def self.execution_errors()
      self.instance.error_msgs
    end

    def self.debug(msg)
      self.instance.logger.debug(msg)
    end

    def self.info(msg)
      self.instance.logger.info(msg)
    end

    def self.warn(msg, backtrace = nil)
      self.instance.logger.warn(msg)
      self.instance.error_msgs <<  { :message => msg, :backtrace => backtrace }
    end

    def self.error(msg, backtrace = nil)
      self.instance.logger.error(msg)
      self.instance.error_msgs << { :message => msg, :backtrace => backtrace }
    end

    def self.fatal(msg, backtrace)
      self.instance.logger.fatal(msg)
      self.instance.logger.fatal(backtrace)
    end

    def self.log_results(params_in, results, agent_name, action_name, top_task_id, task_id, worker_name)
      component_dir = File.join(LOGS_DIR, "#{top_task_id}_#{agent_name}##{action_name}")
      FileUtils.mkdir_p(component_dir, mode: 0754) unless File.directory?(component_dir)

      filename = File.join(component_dir, "#{task_id}_#{action_name}.log")
      File.open(filename, 'w') do |file|
        file.puts('Input data: ')
        file.puts JSON.pretty_generate(params_in)
        file.puts self.instance.all_msgs.join("\n")
        file.puts("Handled by #{worker_name} with results: ")
        file.puts JSON.pretty_generate(results)
      end
    end


    self.singleton_class.after :debug, :info, :warn, :error do |msg, _backtrace|
      self.instance.all_msgs << msg
    end

  end
end
