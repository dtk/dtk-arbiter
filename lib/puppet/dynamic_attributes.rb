###
# Part of legacy mcollective code, marked for refactoring
#

module Arbiter
  module Puppet
    module DynamicAttributes

      def has_dynamic_attributes?(cmps_with_attrs)
        ret = cmps_with_attrs.map do |cmp_with_attrs|
          dyn_attrs = cmp_with_attrs["dynamic_attributes"]||[]
          if !dyn_attrs.empty?
            {
              :cmp_ref => component_ref(cmp_with_attrs),
              :dynamic_attrs => dyn_attrs
            }
          end
        end.compact
        !ret.empty? && ret
      end

      def process_dynamic_attributes!(dynamic_attr_info)
        dyn_attr_assigns = Array.new
        missing_dyn_attrs = Array.new
        dynamic_attr_info.each do |info|
          cmp_ref = info[:cmp_ref]
          info[:dynamic_attrs].each do |dyn_attr|
            if dyn_attr_assign = dynamic_attr_response_el(cmp_ref,dyn_attr)
              dyn_attr_assigns << dyn_attr_assign
            else
              missing_attr = {
                :cmp_ref => cmp_ref,
                :attr => dyn_attr[:name]
              }
              missing_dyn_attrs << missing_attr
            end
          end
        end

        unless missing_dyn_attrs.empty?
          raise_missing_dynamic_attrs!(missing_dyn_attrs)
        end

        dyn_attr_assigns
      end

      def raise_missing_dynamic_attrs!(missing_dyn_attrs)
        errors = missing_dyn_attrs.map do |info|
          "Dynamic Attribute (#{info[:attr]}) is not set by component (#{info[:cmp_ref]})"
        end

        raise MissingDynAttributes, errors.join(', ')
      end

      def component_ref(cmp_with_attrs)
        case cmp_with_attrs["component_type"]
        when "class"
          cmp_with_attrs["name"]
        when "definition"
          defn = cmp_with_attrs["name"]
          unless name_attr = cmp_with_attrs["attributes"].find{|attr|attr["name"] == "name"}
            raise NotFound, "Cannot find the name associated with definition #{defn}"
          end
          "#{cmp_with_attrs["name"]}[#{name_attr["value"]}]"
        else
          raise NotSupported, "Reference to type #{cmp_with_attrs["component_type"]} not treated"
        end
      end

      ###
      # Reading shared variable information
      #
      def exported_variables(cmp_name)
        load_shared_resource(:exported_variables)[cmp_name]
      end

      def exported_resources(cmp_name)
        raise "exported_resources #{cmp_name}"

        (Thread.current[:exported_resources]||{})[cmp_name]
      end

      def exported_files(cmp_name)
        load_shared_resource(:exported_files)[cmp_name]
      end

      ###
      # Puppet executions write marshal files to /tmp/dtk_* we need to load / delete them
      #

      def load_shared_resource(identifier)
        # global variable for shared files
        @shared_resource_map ||= {}

        resource_location = "/tmp/dtk_#{identifier}"
        # return if already processed
        return @shared_resource_map[identifier] if @shared_resource_map[identifier]

        # return if there is no shared file
        return {} unless File.exists?("/tmp/dtk_#{identifier}")

        # load / save to map / delete (not to be mistakenly re-used)
        resource_hash = Marshal.load(File.read(resource_location))
        @shared_resource_map[identifier] = resource_hash
        FileUtils.rm_rf(resource_location)

        @shared_resource_map[identifier]
      end

      ###
      # Returning from element
      #
      def dynamic_attr_response_el(cmp_name, dyn_attr)
        ret = nil
        val =
          if dyn_attr[:type] == "exported_resource"
            dynamic_attr_response_el__exported_resource(cmp_name, dyn_attr)
          elsif dyn_attr[:type] == "default_variable"
            dynamic_attr_response_el__default_attribute(cmp_name, dyn_attr)
          else # assumption only three types: "exported_resource", "default_attribute, (and other can by "dynamic")
            dynamic_attr_response_el__default_attribute(cmp_name, dyn_attr) || dynamic_attr_response_el__dynamic(cmp_name,dyn_attr)
          end
        if val
          ret = {
            :component_name => cmp_name,
            :attribute_name => dyn_attr[:name],
            :attribute_id => dyn_attr[:id],
            :attribute_val => val
          }
        end
        ret
      end

      def dynamic_attr_response_el__exported_resource(cmp_name, dyn_attr)
        ret = nil
        if cmp_exp_rscs = exported_resources(cmp_name)
          cmp_exp_rscs.each do |title,val|
            return val if exp_rsc_match(title, dyn_attr[:title_with_vars])
          end
        else
          Log.debug("No exported resources set for component #{cmp_name}")
        end
        ret
      end

      def dynamic_attr_response_el__default_attribute(cmp_name,dyn_attr)
        ret = nil
        unless cmp_exp_vars = exported_variables(cmp_name)
          Log.debug("No exported varaibles for component #{cmp_name}")
          return ret
        end

        attr_name = dyn_attr[:name]
        unless cmp_exp_vars.has_key?(attr_name)
          Log.debug("No exported variable entry for component #{cmp_name}, attribute #{dyn_attr[:name]})")
          return ret
        end

        cmp_exp_vars[attr_name]
      end

      def dynamic_attr_response_el__dynamic(cmp_name,dyn_attr)
        ret = nil
        attr_name = dyn_attr[:name]
        filepath = (exported_files(cmp_name)||{})[attr_name]
        #TODO; legacy; remove when deprecate
        filepath ||= "/tmp/#{cmp_name.gsub(/::/,".")}.#{attr_name}"
        begin
          val = File.open(filepath){|f|f.read}.chomp
          ret = val unless val.empty?
         rescue Exception
        end
        ret
      end

      ###
      # Matching element
      #

      def exp_rsc_match(title,title_with_vars)
        regexp_str = regexp_string(title_with_vars)
        title =~ Regexp.new("^#{regexp_str}$") if regexp_str
      end

      def regexp_string(title_with_vars)
        if title_with_vars.kind_of?(Array)
          case title_with_vars.first
          when "variable" then ".+"
          when "fn" then regexp_string__when_op(title_with_vars)
          else
            Log.debug("Unexpected first element in title with vars (#{title_with_vars.first})")
            nil
          end
        else
          title_with_vars.gsub(".","\\.")
        end
      end

    end
  end
end