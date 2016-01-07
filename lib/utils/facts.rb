require 'open-uri'
require 'timeout'
require 'yaml'

module Arbiter
  module Utils
    class Facts

      FACT_FILE = '/etc/mcollective/facts.yaml'

      def self.get!(identifier)
        @@fact_hash ||= load_facts
        raise MissingParams, "Missing required fact '#{identifier}' from file '#{FACT_FILE}' aborting action" unless @@fact_hash[identifier.to_s]
        @@fact_hash[identifier.to_s]
      end

      def self.load_facts
        ret = {}
        yaml_file = FACT_FILE
        if File.exists?(yaml_file)
          yaml_facts = YAML.load_file(yaml_file)
          ret.merge!(yaml_facts)
        end
        ret.merge!("pbuilderid" => get_pbuilderid()) unless ret.keys.include?('pbuilderid')
        @@fact_hash = ret
        ret
      end

      def self.get_pbuilderid
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
    end
  end
end