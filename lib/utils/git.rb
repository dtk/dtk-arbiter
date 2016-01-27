require 'rubygems'
require 'grit'
require File.expand_path('../common/gitclient',File.dirname(__FILE__))

MODULE_PATH      = "/etc/puppet/modules"
DTK_PUPPET_PATH  = "/usr/share/dtk/puppet-modules"

module Arbiter
  module Utils
    class Git

      PUPPET_MODULE_PATH  = "/usr/share/dtk/puppet-modules"
      MODULE_PATH         = "/etc/puppet/modules"
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

      def self.pull_modules(version_context,git_server)
        begin
          version_context.each do |vc|
            [:repo, :implementation, :branch].each do |field|
              unless vc[field]
                raise MissingParams, "Version context does not have :#{field} field"
              end
            end

            FileUtils.mkdir_p(DTK_PUPPET_PATH) unless File.directory?(DTK_PUPPET_PATH)

            module_name     = vc[:implementation]
            puppet_repo_dir = "#{DTK_PUPPET_PATH}/#{module_name}"
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
                tries ||= NUMBER_OF_RETRIES
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

            # we remove sym link if it exists
            if File.symlink?(repo_dir)
              FileUtils.rm(repo_dir)
            elsif File.directory?(repo_dir)
              FileUtils.rm_r(repo_dir)
            end

            puppet_dir = "#{DTK_PUPPET_PATH}/#{module_name}/puppet"

            if File.directory?(puppet_dir)
              FileUtils.ln_sf(puppet_dir, repo_dir)
            else
              FileUtils.ln_sf("#{DTK_PUPPET_PATH}/#{module_name}", repo_dir)
            end
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

    end
  end
end