require 'fileutils'
require 'tempfile'

require File.expand_path('../../common/gitclient', __FILE__)
require File.expand_path('../../common/mixin/open3', __FILE__)
require File.expand_path('../../utils/puppet_runner', __FILE__)

module Arbiter
  module Puppet
    class Worker < Common::Worker

      UNKNOWN_SERVICE = 'UNKNOWN'
      NUMBER_OF_RETRIES = 5

      PUPPET_LOG_DIR      = "/var/log/puppet"
      MODULE_PATH         = "/etc/puppet/modules"
      PUPPET_MODULE_PATH  = "/usr/share/dtk/puppet-modules"
      PUPPET_LOG_TASK     = "/usr/share/dtk/tasks/"

      include Common::Open3

      def initialize(message_content, listener)
        super(message_content, listener)

        @service_name    = get(:service_name) || UNKNOWN_SERVICE
        @version_context = get(:version_context)

        # Make sure following is prepared
        FileUtils.mkdir_p(PUPPET_MODULE_PATH) unless File.directory?(PUPPET_MODULE_PATH)
        FileUtils.mkdir_p(PUPPET_LOG_TASK)    unless File.directory?(PUPPET_LOG_TASK)
      end

      def process()
        puppet_run_response = nil

        # we need this to pull our modules
        git_server = Utils::Facts.get!('git-server')

        # pulling modules and preparing environment for changes
        response = pull_modules(get(:version_context), git_server)

        # finally run puppet execution
        puppet_run_response = run()

        notify(success_response)
      end

      def run()
        cmps_with_attrs  = get(:components_with_attributes)
        node_manifest    = get(:node_manifest)
        inter_node_stage = get(:inter_node_stage)
        puppet_version   = get(:puppet_version)

        if puppet_version
          Log.info("Setting user provided puppet version '#{puppet_version}'")
          puppet_version = "_#{puppet_version}_"
        end


        temp_run_file = Tempfile.new('puppet.pp')
        stdout, stderr, status = nil

        begin
          node_manifest.each_with_index do |puppet_manifest, i|
            execute_lines = puppet_manifest || ret_execute_lines(cmps_with_attrs)
            execute_string = execute_lines.join("\n")

            cmd_line =
              [
               "apply",
               #"-l", log_file_path,
               "-d",
               "--debug",
               "--report", "true", "--reports", "r8report"
               #"--storeconfigs_backend", "r8_storeconfig_backend",
               #"-e", execute_string
              ]
            cmd = "/usr/bin/puppet"


            temp_run_file.write(execute_string)
            temp_run_file.close

            command_string = "#{cmd} apply #{temp_run_file.path} --debug --modulepath /etc/puppet/modules"

            stdout, stderr, status, result = Utils::PuppetRunner.execute_cmd_line(command_string)
          end
        rescue SystemExit => e
          if e.status == 0
            if dynamic_attr_info = has_dynamic_attributes?(cmps_with_attrs)
              Log.info("dynamic_attributes = #{dynamic_attr_info.inspect}")
              process_dynamic_attributes!(ret,dynamic_attr_info)
            else
              # all ok
            end
          else
            return notify_of_error("Exit status aborting operation!", :abort_action)
          end
        ensure
          # we log everything
          log_dir          = File.join(PUPPET_LOG_TASK, 'dock-test', "task_id_#{get(:task_id)}")
          last_task_dir    = File.join(PUPPET_LOG_TASK, 'last-task')
          puppet_file_path = File.join(log_dir, 'site-stage-invocation.pp')
          puppet_log_path  = File.join(log_dir, 'site-stage.log')
          exitstatus       = status ? status.exitstatus : 1

          # lets create task dir e.g. /usr/share/dtk/tasks/dock-test/task_id_2147548954
          FileUtils.mkdir_p(log_dir)

          # copy temp file as execution file (which it is)
          FileUtils.cp(temp_run_file.path, puppet_file_path)

          # let us populate log file
          File.open(puppet_log_path, 'w') do |f|
            f.write "Execution completed with exitstatus: #{exitstatus}\n STDERR output:\n"
            f.write stderr
            f.write "STDOUT output:\n"
            f.write stdout
          end

          # create sym link for last_task dir
          FileUtils.ln_sf(log_dir, last_task_dir)
          Log.info("Puppet execution information has been created, and can be found at '#{log_dir}'")
        end
      end

    private

      def exported_resources(cmp_name)
        (Thread.current[:exported_resources]||{})[cmp_name]
      end

      def exported_variables(cmp_name)
        (Thread.current[:exported_variables]||{})[cmp_name]
      end

      def exported_files(cmp_name)
        (Thread.current[:exported_files]||{})[cmp_name]
      end

      def add_imported_collection(cmp_name,attr_name,val,context={})
        p = (Thread.current[:imported_collections] ||= Hash.new)[cmp_name] ||= Hash.new
        p[attr_name] = {"value" => val}.merge(context)
      end

      #
      # Keep in mind that if we are using default format of git url the name of repo is added after ':' symbol.
      # When using ssh style URL repo name is added after '/'
      #
      def git_repo_full_url(git_url, repo_name)
        "#{git_url}/#{repo_name}"
      end

      def pull_module(repo_dir, branch, opts={})
        git_repo = Common::GitClient.new(repo_dir)
        git_repo.pull_and_checkout_branch?(branch,opts)
        true
      end

      def clean_and_clone_module(repo_dir,remote_repo,branch,opts={})
        FileUtils.rm_rf repo_dir if File.exists?(repo_dir)
        git_repo = Common::GitClient.new(repo_dir, :create => true)
        git_repo.clone_branch(remote_repo,branch,opts)
        true
      end

      #
      # This will delete directory or symlink
      #
      def purge_location(repo_dir)
        if File.symlink?(repo_dir)
          FileUtils.rm(repo_dir)
        elsif File.directory?(repo_dir)
          FileUtils.rm_r(repo_dir)
        end
      end

      def pull_modules(version_context,git_server)
        begin
          version_context.each do |vc|
            [:repo, :implementation, :branch].each do |field|
              unless vc[field]
                raise MissingParams, "Version context does not have :#{field} field"
              end
            end

            module_name     = vc[:implementation]
            puppet_repo_dir = "#{PUPPET_MODULE_PATH}/#{module_name}"
            repo_dir        = "#{MODULE_PATH}/#{module_name}"
            remote_repo     = git_repo_full_url(git_server, vc[:repo])

            opts = Hash.new
            opts.merge!(:sha => vc[:sha]) if vc[:sha]

            pull_success = false

            if File.exists?("#{puppet_repo_dir}/.git")
              pull_success = pull_module(puppet_repo_dir, vc[:branch], opts) rescue false
            end

            unless pull_success
              begin
                tries ||= 5
                clean_and_clone_module(puppet_repo_dir, remote_repo,vc[:branch], opts)
               rescue Exception => e
                unless (tries -= 1).zero?
                  Log.info("Re-trying puppet clone for '#{puppet_repo_dir}' becuase of error: #{e.message}, retries left: #{tries}")
                  sleep(1)
                  retry
                end

                # time to give up - sending error response
                raise e
              end
            end

            puppet_dir = "#{PUPPET_MODULE_PATH}/#{module_name}/puppet"

            if File.directory?(puppet_dir)
              FileUtils.ln_sf(puppet_dir, repo_dir)
            else
              FileUtils.ln_sf("#{PUPPET_MODULE_PATH}/#{module_name}", repo_dir)
            end
          end
         ensure
          # this is due to GIT custom againt we are using
          %w{GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE}.each { |var| ENV[var] = nil }
        end
      end

      def ret_execute_lines(cmps_with_attrs)
        ret = Array.new
        @import_statement_modules = Array.new
        cmps_with_attrs.each_with_index do |cmp_with_attrs,i|
          stage = i+1
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