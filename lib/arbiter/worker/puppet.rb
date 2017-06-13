require 'fileutils'
require 'tempfile'
require 'sys/proctable'

module DTK::Arbiter
  class Worker
    class Puppet < self
      require_relative('puppet/dynamic_attributes_mixin')

      UNKNOWN_SERVICE = 'UNKNOWN'
      NUMBER_OF_RETRIES = 5

      PUPPET_LOG_DIR      = "/var/log/puppet"
      PUPPET_MODULE_PATH  = "/etc/puppet/modules"
      MODULE_PATH         = "/usr/share/dtk/modules"
      PUPPET_LOG_TASK     = "/usr/share/dtk/tasks/"
      WAIT_PS_END         = 10
      YUM_LOCK_FILE       = "/var/run/yum.pid"
      YUM_LOCK_RETRIES    = 1

      include CommonMixin::Open3
      include DynamicAttributesMixin

      def initialize(message_content, listener)
        super(message_content, listener)

        @service_name    = get(:service_name) || UNKNOWN_SERVICE
        @version_context = get(:version_context)

        # Make sure this property is set
        ENV['LC_ALL'] = "en_US.UTF-8"

        # Make sure following is prepared
        FileUtils.mkdir_p(MODULE_PATH, mode: 0755) unless File.directory?(MODULE_PATH)
        FileUtils.mkdir_p(PUPPET_LOG_TASK, mode: 0755)    unless File.directory?(PUPPET_LOG_TASK)
      end
      private :initialize

      def process
        # # we need this to pull our modules
        # git_server = Config.git_server

        # # pulling modules and preparing environment for changes
        # Log.info 'Pulling modules from DTK'
        # response = Utils::Git.pull_modules(get(:version_context), git_server, PUPPET_MODULE_PATH)

        # finally run puppet execution
        puppet_run_response = run
        puppet_run_response.merge!(success_response)

        notify(puppet_run_response)
      end

      def run
        cmps_with_attrs  = get(:components_with_attributes)
        node_manifest    = get(:node_manifest)
        inter_node_stage = get(:inter_node_stage)
        puppet_version   = get(:puppet_version)
        # puppet can be executed either from the builtin version installed with omnibus (by default)
        # or from the pulled module
        puppet_execution = get(:puppet_execution) || 'omnibus'

        if puppet_version
          Log.info("Setting user provided puppet version '#{puppet_version}'")
          puppet_version = "_#{puppet_version}_"
        end


        temp_run_file = Tempfile.new('puppet.pp')
        stdout, stderr, exitstatus = nil

        # lets wait for other yum system processes to finish
        check_and_wait_node_initialization

        begin
          node_manifest.each_with_index do |puppet_manifest, i|
            execute_lines = puppet_manifest || ret_execute_lines(cmps_with_attrs)
            execute_string = execute_lines.join("\n")

            if puppet_execution == 'module'
              cmd = "GEM_HOME=#{MODULE_PATH}/puppet #{MODULE_PATH}/puppet/bin/puppet"
            else
              cmd = "/usr/bin/puppet"
            end

            temp_run_file.write(execute_string)
            temp_run_file.close


            command_string = "#{cmd} apply #{temp_run_file.path} --debug --modulepath #{MODULE_PATH}"

            yum_lock_retries = YUM_LOCK_RETRIES

            begin
              stdout, stderr, exitstatus, result = Utils::PuppetRunner.execute_cmd_line(command_string)

              unless exitstatus == 0
                # we check if there is yum lock
                if yum_lock_retries != 0 && (stderr||'').include?(YUM_LOCK_FILE)
                  raise YumLock, "Yum lock has been detected!"
                end

                raise ActionAbort, "Not able to execute puppet code, exitstatus: #{exitstatus}, error: #{stderr}"
              end
            rescue YumLock => e
              # we wait for YUM process to finish and than we try again
              Log.warn("YUM Lock has been detected, initiating wait sequence for running YUM process.")
              wait_for_yum_lock_release
              yum_lock_retries -= 1
              retry
            end

            response = {}

            if dynamic_attr_info = has_dynamic_attributes?(cmps_with_attrs)
              Log.debug("Found dynamic attributes, calculating ...")
              dynamic_attributes = process_dynamic_attributes!(dynamic_attr_info)
              response[:dynamic_attributes] = dynamic_attributes
              Log.debug("Found dynamic attributes, setting them to: #{dynamic_attributes.inspect}")
            end

            return response
          end
        ensure
          # we log everything
          log_dir          = File.join(PUPPET_LOG_DIR, get(:service_name), "task_id_#{get(:task_id)}")
          task_dir         = File.join(PUPPET_LOG_TASK, get(:service_name), "task_id_#{get(:task_id)}")
          last_task_dir    = File.join(PUPPET_LOG_TASK, 'last-task')
          puppet_file_path = File.join(task_dir, 'site-stage-invocation.pp')
          puppet_log_path  = File.join(log_dir, 'site-stage.log')

          # lets create task dir e.g. /usr/share/dtk/tasks/dock-test/task_id_2147548954
          FileUtils.mkdir_p(log_dir, mode: 0755)
          FileUtils.mkdir_p(task_dir, mode: 0755)

          # copy temp file as execution file (which it is)
          FileUtils.cp(temp_run_file.path, puppet_file_path)

          # let us populate log file
          File.open(puppet_log_path, 'w') do |f|
            f.write "Execution completed with exitstatus: #{exitstatus}\n"
            f.write "Errors:\n#{stderr}" if stderr
            f.write "Full output:\n"
            f.write stdout
          end

          # make sure that correct permissions are set on puppet files
          File.chmod(0755, puppet_file_path)
          File.chmod(0755, puppet_log_path)

          # create sym link for last_task dir
          FileUtils.rm(last_task_dir) if File.directory?(last_task_dir)
          FileUtils.ln_s(task_dir, last_task_dir)
          # create symlink for last puppet log
          FileUtils.ln_sf(puppet_log_path, "#{PUPPET_LOG_DIR}/last.log")
          FileUtils.ln_sf(puppet_log_path, task_dir)
          Log.info("Puppet execution information has been created, and can be found at '#{log_dir}'")
        end
      end

    private

      ##
      # On amazon linux instances there is a process S52cloud-config, this process uses yum and as such has to end before we can start puppet apply.
      # Following code finds that process and waits for it to finish
      #
      def check_and_wait_node_initialization
        cloud_config_ps = Sys::ProcTable.ps.select { |process| process.comm.match(/(S\d+cloud\-config)|(update\-motd)|(^rc$)/) }
        cloud_init_detected = false

        cloud_config_ps.each do |cc_ps|
          cloud_init_detected = true
          Log.info("Cloud config process detected! Process (#{cc_ps.pid}) #{cc_ps.comm} is in state '#{cc_ps.state}', waiting for it to finish ...")
          while process_exists?(cc_ps.pid) do
            sleep(WAIT_PS_END)
          end
          Log.info("Cloud config process has finished! Resuming puppet apply ...")
        end
      end

      def wait_for_yum_lock_release
        if File.exists?(YUM_LOCK_FILE)
          pid = File.read(YUM_LOCK_FILE)
          pid = (pid||'').strip.to_i

          Log.info("Puppet execution is waiting for YUM process (#{pid}) to finish")
          while process_exists?(pid) do
            sleep(WAIT_PS_END)
          end
          Log.info("Puppet execution is retrying last action, since YUM processed finished")
        end
      end

      def log_processes_to_file
        output = `ps -A --forest`
        Log.log_to_file("process_tree_#{Time.now.to_i}", output)
      end

      def process_exists?(pid)
        Sys::ProcTable.ps(pid)
      end

      def add_imported_collection(cmp_name,attr_name,val,context={})
        p = (Thread.current[:imported_collections] ||= Hash.new)[cmp_name] ||= Hash.new
        p[attr_name] = {"value" => val}.merge(context)
      end

      def ret_execute_lines(cmps_with_attrs)
        ret = Array.new
        @import_statement_modules = Array.new
        cmps_with_attrs.each_with_index do |cmp_with_attrs,i|
          stage = i + 1
          module_name = cmp_with_attrs["module_name"]
          ret << "stage{#{quote_form(stage)} :}"
          attrs = process_and_return_attr_name_val_pairs(cmp_with_attrs)
          stage_assign = "stage => #{quote_form(stage)}"
          case cmp_with_attrs["component_type"]
           when "class"
            cmp = cmp_with_attrs["name"]
            raise "No component name" unless cmp
            if imp_stmt = needs_import_statement?(cmp,module_name)
              ret << imp_stmt
            end

            #TODO: see if need \" and quote form
            attr_str_array = attrs.map{|k,v|"#{k} => #{process_val(v)}"} + [stage_assign]
            attr_str = attr_str_array.join(", ")
            ret << "class {\"#{cmp}\": #{attr_str}}"
           when "definition"
            defn = cmp_with_attrs["name"]
            raise "No definition name" unless defn
            name_attr = nil
            attr_str_array = attrs.map do |k,v|
              if k == "name"
                name_attr = quote_form(v)
                nil
              else
                "#{k} => #{process_val(v)}"
              end
            end.compact
            attr_str = attr_str_array.join(", ")
            raise "No name attribute for definition" unless name_attr
            if imp_stmt = needs_import_statement?(defn,module_name)
              ret << imp_stmt
            end
            #putting def in class because defs cannot go in stages
            class_wrapper = "stage#{stage.to_s}"
            ret << "class #{class_wrapper} {"
            ret << "#{defn} {#{name_attr}: #{attr_str}}"
            ret << "}"
            ret << "class {\"#{class_wrapper}\": #{stage_assign}}"
          end
        end
        size = cmps_with_attrs.size
        if size > 1
          ordering_statement = (1..cmps_with_attrs.size).map{|s|"Stage[#{s.to_s}]"}.join(" -> ")
          ret << ordering_statement
        end

        if attr_val_stmts = get_attr_val_statements(cmps_with_attrs)
          ret += attr_val_stmts
        end
        ret
      end

      #removes imported collections and puts them on global array
      def process_and_return_attr_name_val_pairs(cmp_with_attrs)
        ret = Hash.new
        return ret unless attrs = cmp_with_attrs["attributes"]
        cmp_name = cmp_with_attrs["name"]
        attrs.each do |attr_info|
          attr_name = attr_info["name"]
          val = attr_info["value"]
          case attr_info["type"]
           when "attribute"
            ret[attr_name] = val
          when "imported_collection"
            add_imported_collection(cmp_name,attr_name,val,{"resource_type" => attr_info["resource_type"], "import_coll_query" =>  attr_info["import_coll_query"]})
          else raise "unexpected attribute type (#{attr_info["type"]})"
          end
        end
        ret
      end

      def get_attr_val_statements(cmps_with_attrs)
        ret = Array.new
        cmps_with_attrs.each do |cmp_with_attrs|
          (cmp_with_attrs["dynamic_attributes"]||[]).each do |dyn_attr|
            if dyn_attr[:type] == "default_variable"
              qualified_var = "#{cmp_with_attrs["name"]}::#{dyn_attr[:name]}"
              ret << "r8::export_variable{'#{qualified_var}' :}"
            end
          end
        end
        ret.empty? ? nil : ret
      end

      def needs_import_statement?(cmp_or_def,module_name)
        return nil if cmp_or_def =~ /::/
        return nil if @import_statement_modules.include?(module_name)
        @import_statement_modules << module_name
        "import '#{module_name}'"
      end

      def process_val(val)
        #a guarded val
        if val.kind_of?(Hash) and val.size == 1 and val.keys.first == "__ref"
          "$#{val.values.join("::")}"
        else
          quote_form(val)
        end
      end

    end
  end
end
