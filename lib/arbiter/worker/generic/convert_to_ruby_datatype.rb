module DTK::Arbiter
  class Worker::Generic
    module ConvertToRubyDataype
      def self.convert_attributes(attributes_with_metadata)
        attributes_with_metadata.inject({}) { |h, (name, info)| h.merge(name => convert_attribute(info)) }
      end
      
      private
      
      def self.convert_attribute(attribute_info)
        value = attribute_info[:value]
        if value.nil?
          nil
        else
          datatype = (attribute_info[:datatype] || :string).to_sym
          case datatype
          when :string, :integer, :port then convert_to(datatype, value)
          when :boolean then  convert_to_boolean(value)
          when :hash then  convert_to_hash(value)
          when :array then  convert_to_array(value)
          when :json then value # TODO: this type might get depreacted

          else
            handle_datatype_error(value, "Unknown datatype '#{datatype}'")
          end
        end
      end
      CONVERT_INFO = {
        string: {
          convert_method: :to_s
        },
        integer: {
          convert_method: :to_i
        },
        port: {
          convert_method: :to_i
        }
      }
      def self.convert_to(type, value)
        unless convert_method = (CONVERT_INFO[type] || {})[:convert_method]
          handle_datatype_error(value, "Type '#{type}' not in CONVERT_INFO")
        else
          if value.respond_to?(convert_method)
            value.send(convert_method)
          else
            handle_data_type_mismatch(type, value)
          end
        end
      end

      def self.convert_to_boolean(value)
        case value.to_s
        when 'true' then true
        when 'false' then false
        else
          handle_data_type_mismatch(:boolean, value)
        end
      end

      def self.convert_to_array(value)
        value.kind_of?(::Array) ? value : handle_data_type_mismatch(:array, value)
      end

      def self.convert_to_hash(value)
        value.kind_of?(::Hash) ? value : handle_data_type_mismatch(:hash, value)
        value
      end

      def self.convert_to_json(value)
        value
      end

      def self.handle_data_type_mismatch(type, value)
        handle_datatype_error(value, "Non #{type} value: #{value.inspect}")
      end

      def self.handle_datatype_error(value, err_message)
        Log.error err_message
        value
      end

    end
  end
end
