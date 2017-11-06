require 'rubygems' #TODO: is this needed?

DTK_MODULE_PATH  = "/usr/share/dtk/modules"

module DTK::Arbiter
  module Utils
    class Git
      require_relative('git/client')

      NUMBER_OF_RETRIES = 5

      def self.git_repo_full_url(git_url, repo_name)
        "#{git_url}/#{repo_name}"
      end

      def self.clean_and_clone_module(repo_dir,remote_repo,branch,opts={})
        FileUtils.rm_rf repo_dir if File.exists?(repo_dir)
        git_repo = Client.new(repo_dir, :create => true)
        git_repo.clone_branch(remote_repo,branch,opts)
        true
      end

      #
      # This will delete directory or symlink
      #
      def self.purge_location(repo_dir)
        if File.symlink?(repo_dir)
          FileUtils.rm(repo_dir)
        elsif File.directory?(repo_dir)
          FileUtils.rm_r(repo_dir)
        end
      end

      def self.pull_modules(modules,git_server,opts = {})
        clone_location = opts[:clone_location] || DTK_MODULE_PATH
        symlink_location = opts[:symlink_location] || nil

        unless Config.git_pull_modules
          Log.info("Skipping module pull since 'git_pull_modules' is set to false in arbiter.cfg")
          return true
        end
        begin

          # check if modules are passed in deprecated format
          # if so, convert
          modules = convert_version_context(modules) if modules.kind_of?(Array)

          modules.each do |k,v|
            [:repo, :branch].each do |field|
              unless v[field]
                raise MissingParams, "Modules info does not have :#{field} field"
              end
            end

            FileUtils.mkdir_p(clone_location) unless File.directory?(clone_location)

            module_name     = k.to_s
            module_repo_dir = "#{clone_location}/#{module_name}"
            repo_dir        = "#{symlink_location}/#{module_name}"
            remote_repo     = git_repo_full_url(git_server, v[:repo])

            opts = Hash.new
            opts.merge!(:sha => v[:sha]) if v[:sha]

            pull_success = false

            if File.exists?("#{module_repo_dir}/.git")
              pull_success = pull_module(module_repo_dir, v[:branch], opts) rescue false
            end

            unless pull_success
              begin
                tries ||= NUMBER_OF_RETRIES
                clean_and_clone_module(module_repo_dir, remote_repo,v[:branch], opts)
               rescue Exception => e
                unless (tries -= 1).zero?
                  Log.info("Re-trying module clone for '#{module_repo_dir}' becuase of error: #{e.message}, retries left: #{tries}")
                  sleep(1)
                  retry
                end

                # time to give up - sending error response
                raise e
              end
            end

            # we remove sym link if it exists
            if File.symlink?(repo_dir)
              FileUtils.rm(repo_dir)
            elsif File.directory?(repo_dir)
              FileUtils.rm_r(repo_dir)
            end

            # symlink the module to designated location  
            FileUtils.ln_sf("#{clone_location}/#{module_name}", repo_dir) if symlink_location
          end
         ensure
          # this is due to GIT custom againt we are using
          %w{GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE}.each { |var| ENV[var] = nil }
        end
      end

      def self.pull_module(repo_dir,branch,opts={})
        if File.exist?(repo_dir)
          # check if local repo is identical to the remote one
          local_repo = ::Grit::Repo.new(repo_dir)
          local_sha = local_repo.commits("HEAD").first.id
          local_repo_unchanged = local_repo.status.changed.empty?
          # we don't need to clone if the local SHA is identical to the remote one
          # unless the local repo has changes
          # TO-DO: consider making the local repo changed check optional via config gile
          # to allow testing by making local changes
          return true if (local_sha == opts[:sha]) && local_repo_unchanged
        end
        git_repo = Client.new(repo_dir)
        git_repo.pull_and_checkout_branch?(branch,opts)
      end

      def self.clean_and_clone_module(repo_dir,remote_repo,branch,opts={})
        FileUtils.rm_rf repo_dir if File.exists?(repo_dir)
        git_repo = Client.new(repo_dir,:create=>true)
        git_repo.clone_branch(remote_repo,branch,opts)
      end


      #
      # Keep in mind that if we are using default format of git url the name of repo is added after ':' symbol.
      # When using ssh style URL repo name is added after '/'
      #
      def self.git_repo_full_url(git_url, repo_name)
        "#{git_url}/#{repo_name}"
      end

      def self.log_error(e)
        log_error = ([e.inspect]+backtrace_subset(e)).join("\n")
        Log.info("\n----------------error-----\n#{log_error}\n----------------error-----")
      end

      def self.backtrace_subset(e)
        e.backtrace[0..10]
      end

      # used for converting from old deprecated version_context module info format
      def self.convert_version_context(version_context)
        modules = Hash.new
        version_context.each do |vc|
          name = vc[:implementation]
          repo = vc[:repo]
          branch = vc[:branch]
          sha = vc[:sha]
          module_info = {:repo => repo, :branch => branch}
          module_info[:sha] = sha if sha
          module_hash = {name.to_sym => module_info}
          modules.merge!(module_hash)
        end
        modules
      end
    end
  end
end
