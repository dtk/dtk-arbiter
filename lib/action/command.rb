require 'open3'
require 'timeout'



module Arbiter
  module Action

    ##
    # This is container for command as received from Node Agent
    #

    class Command

      attr_accessor :command_type, :command, :process, :backtrace

      ##
      # command         - string to be run on system, e.g. ifconfig
      # type            - type of command e.g. syscall, ruby
      # if              - callback to be run if exit status is  = 0
      # unless          - callback to be run if exit status is != 0
      # stdout_redirect - redirect all output to stdout
      #

      STDOUT_REDIRECT = ' 2>&1'
      STREAM_TIMEOUT  = 5

      def initialize(value_hash)
        # DEBUG SNIPPET >>> REMOVE <<<
        require 'ap'
        ap "VALUE HASH"
        ap value_hash
        @command_type    = value_hash[:type]
        @command         = value_hash[:command]
        @stdout_redirect = !!value_hash[:stdout_redirect]

        @if              = value_hash[:if]
        @unless          = value_hash[:unless]

        @timeout         = (value_hash[:timeout] || 0).to_i

        @env_vars        = value_hash[:env_vars]

        if @if && @unless
          Log.warn "Unexpected case, both if/unless conditions have been set for command #{@command}(#{@command_type})"
        end
      end

      ##
      # Creates Posix Spawn of given process
      #
      def start_task
        begin

          Commander.set_environment_variables(@env_vars)

          # DEBUG SNIPPET >>> REMOVE <<<
          require 'ap'
          ap self

          results = capture3_with_timeout(formulate_command)

          @out = results[:stdout]
          @err = results[:stderr]
          @process_status = results[:status]

          @error_message = "Timeout (#{@timeout} sec) for this action has been exceeded" if results[:timeout]

        rescue Exception => e
          @error_message = e.message
          @backtrace = e.backtrace
          Log.error(@error_message, @backtrace)
        ensure
          Commander.clear_environment_variables(@env_vars)
        end
      end

      ##
      # Checks if there is callaback present, callback beeing if/unless command
      #
      def callback_pending?
        @if || @unless
      end

      def is_positioning?
        'file'.eql?(@command_type)
      end

      ##
      # Returns true/false based on condition data and result of process
      #
      def run_condition_task
        condition_command   = @if
        condition_command ||= @unless

        # this is needed since Timeout block will not allow initialization of new variables
        condition_process_status = nil

        begin
          Timeout.timeout(@timeout) do
            _out, _err, condition_process_status = Open3.capture3(condition_command)
          end
        rescue Exception => e
          # do not log error in cases it was expected. Meaning that 'unless' condition was set.
          Log.warn("Condition command '#{condition_command}' ran into an exception, message: #{e.message}") unless @unless
          # return true if unless condition was used
          return @unless ? true : false
        end

        return condition_process_status.exitstatus > 0 ? false : true if @if
        return condition_process_status.exitstatus > 0 ? true  : false if @unless
      end

      def exited?
        return true if @error_message
        @process_status.exited?
      end

      def started?
        return true if @error_message
        !!@process_status
      end

      def exitstatus
        return 1 if @error_message
        @process_status.exitstatus
      end

      def out
        return '' if @error_message
        @out.encode('UTF-8', :invalid => :replace, :undef => :replace, :replace => '')
      end

      def err
        return @error_message if @error_message
        @err.encode!('UTF-8', :invalid => :replace, :undef => :replace, :replace => '')
      end

      def to_s
        "#{formulate_command} (#{command_type})"
      end

    private

      ##
      # Open3 method extended with timeout, more info https://gist.github.com/pasela/9392115
      #

      def capture3_with_timeout(*cmd)
        spawn_opts = Hash === cmd.last ? cmd.pop.dup : {}
        opts = {
          :stdin_data => "",
          :timeout    => @timeout,
          :signal     => :TERM,
          :kill_after => nil,
        }

        in_r,  in_w  = IO.pipe
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_w.sync = true

        spawn_opts[:in]  = in_r
        spawn_opts[:out] = out_w
        spawn_opts[:err] = err_w

        result = {
          :pid     => nil,
          :status  => nil,
          :stdout  => nil,
          :stderr  => nil,
          :timeout => false,
        }

        out_reader = nil
        err_reader = nil
        wait_thr = nil

        begin
          # DEBUG SNIPPET >>> REMOVE <<<
          require 'ap'
          ap "START HERE!!!!!"
          ap opts
          ap cmd
          ap spawn_opts
          Timeout.timeout(opts[:timeout]) do
            result[:pid] = spawn(*cmd, spawn_opts)
            wait_thr = Process.detach(result[:pid])
            in_r.close
            out_w.close
            err_w.close

            out_reader = Thread.new { out_r.read }
            err_reader = Thread.new { err_r.read }

            in_w.close

            result[:status] = wait_thr.value
          end
        rescue Timeout::Error
          result[:timeout] = true
          pid = result[:pid]
          Process.kill(opts[:signal], pid)
          if opts[:kill_after]
            unless wait_thr.join(opts[:kill_after])
              Process.kill(:KILL, pid)
            end
          end
        ensure
          result[:status] = wait_thr.value if wait_thr
          begin
            # there is a bug where there is infinite leg on out_reader (e.g. hohup) commands
            Timeout.timeout(STREAM_TIMEOUT) do
              result[:stdout] = out_reader.value if out_reader
              result[:stderr] = err_reader.value if err_reader
            end
          rescue Timeout::Error
            result[:stdout] ||= ''
            result[:stderr] ||= ''
          end
          out_r.close unless out_r.closed?
          err_r.close unless err_r.closed?
        end

        result
      end

      #
      # Based on stdout-redirect flag
      #
      def formulate_command
        @command
      end

    end
  end
  end
