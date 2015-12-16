require 'puppet'

require File.expand_path('../../common/mixin/open3', __FILE__)


module Arbiter
  module Utils
    class PuppetRunner

      extend ::Arbiter::Common::Open3

      PUPPET_RUNNABLE = '/usr/bin/puppet'

      def self.execute_cmd_line(command_string)
        Log.debug("Puppet Runner executing command line: '#{command_string}'")
        capture3_with_timeout(command_string)
      end

      def self.execute(puppet_definition, resource_hash)
        # we need to create command string
        resource_str = "{#{resource_hash[:name]}:"
        value_pairs = resource_hash.collect { |k,v| "#{k}=>'#{v}'" }
        resource_str += value_pairs.join(', ') + '}'

        cmd = "#{PUPPET_RUNNABLE} apply -e \"#{puppet_definition} #{resource_str}\""
        Log.debug("Puppet Runner executing: #{cmd}")

        stdout, stderr, status, result = capture3_with_timeout(cmd)

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

