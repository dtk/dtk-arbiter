module DTK::Arbiter
  module Utils
    module Sanitize
      HIDDEN_VALUE = '***'

      def self.sanitize_message(msg)
        msg[:agent_ssh_key_private] = HIDDEN_VALUE if msg.key?(:agent_ssh_key_private)
        return msg unless msg[:protocol_version]
        sanitized_attributes = msg[:attributes].inject({}) do |h, (type, attributes_hash)| 
          h.merge(type => attributes_hash.inject({}) { |h, (name, info)| h.merge(name => sanitize_attribute(name, info)) })
        end
        msg.merge(attributes: sanitized_attributes)
      end
      
      private
      
      def self.sanitize_attribute(name, attr_info)
        (attr_info[:hidden] || ['password', 'secret'].any? { |pattern| name.downcase.include? pattern }) ? attr_info.merge(value: HIDDEN_VALUE) : attr_info 
      end
    end
  end
end
