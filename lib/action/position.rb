require 'thread'
require 'git'
require 'fileutils'
require File.expand_path('../../utils/permission', __FILE__)


module Arbiter
  module Action
    class Position

      attr_accessor :position_file_info, :exitstatus, :started, :out, :err, :backtrace, :owner, :mode

      def initialize(command_hash)
        source_info, target_info = command_hash[:source], command_hash[:target]

        @exited     = false
        @started    = false
        @exitstatus = 0

        @type    = source_info[:type].to_sym
        @git_url = source_info[:url]
        @branch  = source_info[:ref] || 'master'
        @content = source_info[:content]
        @owner   = command_hash[owner]

        if command_hash[:mode]
          if Utils::Permission.check(command_hash[:mode])
            @mode   = command_hash[:mode].to_s.oct
          else
            trigger_error("Permissions '#{command_hash[:mode]}' are not valid, aborting operation")
          end
        end

        @env_vars = command_hash[:env_vars]

        @target_path = target_info[:path]
      end

      def start_task()
        @started = true

        # for cases when there was an error
        return if @exited

        prepare_path()

        Commander.set_environment_variables(@env_vars)

        begin
          case @type
          when :git
            position_git()
          when :in_payload
            position_in_payload()
          end
        rescue Exception => e
          cleanup_path()
          trigger_error(e.message, 1, e.backtrace)
        ensure
          Commander.clear_environment_variables(@env_vars)
        end

      end

      def exited?
        @exited
      end

      def started?
        @started
      end

      def callback_pending?
        # not supported at the moment
        false
      end

      def to_s
        :git.eql?(@type) ? "git clone #{@git_url}:#{@branch} > #{@target_path}" : "create #{@target_path} with provided content"
      end

    private

      def trigger_error(error_message, err_status = 1, error_backtrace = nil)
        @err = error_message
        Log.error(error_message, error_backtrace)
        @exitstatus = err_status
        @started = true
        @exited  = true
      end

      def position_git()
        unless File.directory?(@target_path)
          begin
            tries ||= 2
            g_repo = Git.clone("#{@git_url}", '', :path => @target_path, :branch => @branch)
            Log.info("Positioner successfully cloned git repository '#{@git_url}@#{@branch}' to location '#{@target_path}'")
          rescue Exception => e
            cleanup_path()
            retry unless (tries -= 1).zero?
            trigger_error("Positioner unable to clone provided url #{@git_url}. Reasone: #{e.message}", 1, e.backtrace)
          end
        else
          Log.warn("Positioner detected folder '#{@target_path}' skipping git clone")
        end

        @exited = true
      end

      def position_in_payload()
        # write to file using content from payload
        file = File.open(@target_path, 'w')
        file.write(@content)

        if @owner
          begin
            FileUtils.chown(@owner, nil, file.path)
          rescue Exception => e
            Log.warn("Not able to set owner '#{@owner}', reason: " + e.message)
          end
        end

        if @mode
          begin
            FileUtils.chmod(@mode, file.path)
          rescue Exception => e
            Log.warn("Not able to set chmod permissions '#{@mode}', reason: " + e.message)
          end
        end

        Log.info("Positioner successfully created 'IN_PAYLOAD' file '#{@target_path}'")
        file.close
        @exited = true
      end

      def prepare_path()
        # create necessery dir structure
        FileUtils.mkdir_p(File.dirname(@target_path))

        @target_path
      end

      def cleanup_path()
        FileUtils.rm_rf(@target_path)
      end

    end
  end
end