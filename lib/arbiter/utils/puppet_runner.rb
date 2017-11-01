module DTK::Arbiter
  module Utils
    class PuppetRunner

      extend CommonMixin::Open3

      PUPPET_RUNNABLE = '/usr/bin/puppet'
      STDOUT_REDIRECT = ' 2>&1'

      def self.execute_cmd_line(command_string)
        command_string = "#{command_string} #{STDOUT_REDIRECT}"
        Log.debug("Puppet Runner executing command line: '#{command_string}'")

        # we redirect all to STDOUT so that we can have inside in order of status / error logs
        stdout, stderr, status, result = capture3_with_timeout(command_string)
        exitstatus = status.exitstatus

        # we extract, puppet lines with error
        error_lines = stdout.split("\n").select { |line| line.match(/Error:|E: Could not get lock/)}

        # we make sure that error lines are here, and that exitstatus matches this scenario
        unless error_lines.empty?
          stderr = error_lines.join("\n")
          exitstatus = 1 if exitstatus == 0
        end

        [stdout, stderr, exitstatus, result]
      end

      def self.execute(puppet_definition, resource_hash)
        # we need to create command string
        resource_str = "{#{resource_hash[:name]}:"
        value_pairs = resource_hash.collect { |k,v| "#{k}=>'#{v}'" }
        resource_str += value_pairs.join(', ') + '}'

        cmd = "#{PUPPET_RUNNABLE} apply -e \"#{puppet_definition} #{resource_str}\""
        Log.debug("Puppet Runner executing: #{cmd}")

        Bundler.with_clean_env do
          stdout, stderr, status, result = capture3_with_timeout(cmd)
        end

        # 0 should be last output if success, since that is the exit code we want
        unless status == 0
          error_msg = stderr.split("\n").join('; ')
          Log.error("Puppet Runner error executing command '#{cmd}', output: #{error_msg}")
          raise ActionAbort, "Puppet Runner error running puppet definition '#{puppet_definition}' - output: #{error_msg}"
        end

        Log.debug("Puppet Runner ran definition #{puppet_definition} with success!")
      end

    end
  end
end

