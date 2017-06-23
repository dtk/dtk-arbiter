module DTK::Arbiter
  module Utils
    class Setup

    	require 'fileutils'

      def self.run
      	# make sure cron job is enabled
      	ensure_cron
      end

      def self.ensure_cron
      	cron_file_path = File.expand_path(File.join(File.dirname(__FILE__), '../../../', 'etc/dtk-arbiter-cron'))
      	cron_file_target = '/etc/cron.d/dtk-arbiter-cron'
      	# install the cron file if not already there
      	# or modified
      	if !File.exist?(cron_file_target) || !FileUtils.identical?(cron_file_path, cron_file_target)
    	    Log.info('Installing/updating dtk-arbiter cron file')
    	    FileUtils.cp(cron_file_path, cron_file_target)
    	    FileUtils.chmod 0755, '/usr/bin/ruby'
      	end
      end

    end
  end
end
