require 'puppet'

class Puppet::Settings
  def initialize_global_settings(args = [])
    #raise Puppet::DevError, "Attempting to initialize global default settings more than once!" if global_defaults_initialized?
    return if global_defaults_initialized?
    # The first two phases of the lifecycle of a puppet application are:
    # 1) Parse the command line options and handle any of them that are
    #    registered, defined "global" puppet settings (mostly from defaults.rb).
    # 2) Parse the puppet config file(s).
    parse_global_options(args)
    parse_config_files
    @global_defaults_initialized = true
  end
end

module Arbiter
  module Utils
    class PuppetRunner

      def self.apply(puppet_definition, resource_hash)
        if Puppet.settings.respond_to?(:initialize_global_settings)
          Puppet.settings.initialize_global_settings
        end

        if Puppet.settings.respond_to?(:initialize_app_defaults)
          Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
        end

        Puppet.settings.initialize_global_settings
        Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))


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

