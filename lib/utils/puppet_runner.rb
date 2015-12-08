require 'puppet'

module Arbiter
  module Utils
    class PuppetRunner

      def self.apply(puppet_definition, resource_hash)
        # DEBUG SNIPPET >>> REMOVE <<<
        require (RUBY_VERSION.match(/1\.8\..*/) ? 'ruby-debug' : 'debugger');Debugger.start; debugger
        if Puppet.settings.respond_to?(:initialize_global_settings)
          Puppet.settings.initialize_global_settings
        end

        if Puppet.settings.respond_to?(:initialize_app_defaults)
          Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
        end

        pup = Puppet::Type.type(:ssh_authorized_key).new(resource_hash)
        catalog = Puppet::Resource::Catalog.new
        catalog.add_resource pup
        catalog.apply()


        Log.info("Puppet Runner, INPUT :")
        Log.info(puppet_definition)
        Log.info(resource_hash.inspect)
        Log.info("########################################################################")

        pup = Puppet::Type.type(puppet_definition).new(resource_hash)
        catalog = Puppet::Resource::Catalog.new
        catalog.add_resource pup
        catalog.apply()

        Log.info("Puppet Runner, OUTPUT: ")
        Log.info(Thread.current[:report_status])
        Log.info(Thread.current[:report_info])
        Log.info("########################################################################")
        true
      end

    end
  end
end

