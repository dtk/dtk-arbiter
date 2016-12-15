require 'rubygems'
require 'grit'
require File.expand_path('../common/gitclient',File.dirname(__FILE__))

DTK_MODULE_PATH  = "/usr/share/dtk/modules"

module Arbiter
  module Utils
    class Git

      NUMBER_OF_RETRIES = 5

      def self.git_repo_full_url(git_url, repo_name)
        "#{git_url}/#{repo_name}"
      end

      def self.clean_and_clone_module(repo_dir,remote_repo,branch,opts={})
        FileUtils.rm_rf repo_dir if File.exists?(repo_dir)
        git_repo = Common::GitClient.new(repo_dir, :create => true)
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

      def self.pull_modules(modules,git_server,symlink_location = nil)
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

            FileUtils.mkdir_p(DTK_MODULE_PATH) unless File.directory?(DTK_MODULE_PATH)

            module_name     = k.to_s
            module_repo_dir = "#{DTK_MODULE_PATH}/#{module_name}"
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
            FileUtils.ln_sf("#{DTK_MODULE_PATH}/#{module_name}", repo_dir) if symlink_location
          end
         ensure
          # this is due to GIT custom againt we are using
          %w{GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE}.each { |var| ENV[var] = nil }
        end
      end

      def self.pull_module(repo_dir,branch,opts={})
        git_repo = ::Arbiter::Common::GitClient.new(repo_dir)
        git_repo.pull_and_checkout_branch?(branch,opts)
      end

      def self.clean_and_clone_module(repo_dir,remote_repo,branch,opts={})
        FileUtils.rm_rf repo_dir if File.exists?(repo_dir)
        git_repo = ::Arbiter::Common::GitClient.new(repo_dir,:create=>true)
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