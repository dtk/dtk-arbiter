require 'rubygems'
require 'grit'
require File.expand_path('../common/gitclient',File.dirname(__FILE__))

ModulePath                  = "/etc/puppet/modules"
DTKPuppetModulePath         = "/usr/share/dtk/puppet-modules"

module Arbiter
  module Utils
    class Git

      NUMBER_OF_RETRIES = 5
      @log = Log.instance

      def self.pull_modules(version_context,git_server)
        ret = Response.new
        ENV['GIT_SHELL'] = nil #This is put in because if vcsrepo Puppet module used it sets this
        error_backtrace = nil
        begin
          version_context.each do |vc|
            [:repo,:implementation,:branch].each do |field|
              unless vc[field]
                raise "version context does not have :#{field} field"
              end
            end

            FileUtils.mkdir_p(DTKPuppetModulePath) unless File.directory?(DTKPuppetModulePath)

            module_name     = vc[:implementation]
            puppet_repo_dir = "#{DTKPuppetModulePath}/#{module_name}"
            repo_dir        = "#{ModulePath}/#{module_name}"
            remote_repo     = git_repo_full_url(git_server, vc[:repo])

            opts = Hash.new
            opts.merge!(:sha => vc[:sha]) if vc[:sha]

            clean_and_clone = true
            if File.exists?("#{puppet_repo_dir}/.git")
              pull_err = trap_and_return_error do
                pull_module(puppet_repo_dir, vc[:branch], opts)
              end
              # clean_and_clone set so if pull error then try again, this time cleaning dir and freshly cleaning
              clean_and_clone = !pull_err.nil?
            end

            if clean_and_clone
              begin
                tries ||= NUMBER_OF_RETRIES
                clean_and_clone_module(puppet_repo_dir, remote_repo,vc[:branch], opts)
               rescue Exception => e
                # to achieve idempotent behavior; fully remove directory if any problems
                FileUtils.rm_rf puppet_repo_dir
                unless (tries -= 1).zero?
                  @log.info("Re-trying last command becuase of error: #{e.message}, retries left: #{tries}")
                  sleep(1)
                  retry
                end
                # TODO: not used now
                error_backtrace = backtrace_subset(e)
                raise e
              end
            end

            # remove symlink if exist already
            if File.symlink?(repo_dir)
              FileUtils.rm(repo_dir)
            elsif File.directory?(repo_dir)
              FileUtils.rm_r(repo_dir)
            end

            puppet_dir = "#{DTKPuppetModulePath}/#{module_name}/puppet"

            if File.directory?(puppet_dir)
              FileUtils.ln_sf(puppet_dir, repo_dir)
            else
              FileUtils.ln_sf("#{DTKPuppetModulePath}/#{module_name}", repo_dir)
            end
          end
          ret.set_status_succeeded!()
         rescue Exception => e
          log_error(e)
          ret.set_status_failed!()
          ret.merge!(error_info(e))
         ensure
          #TODO: may mot be needed now switch to grit
          #git library sets these vars; so reseting here
          %w{GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE}.each{|var|ENV[var]=nil}
        end
        ret
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

      def self.git_repo_full_url(git_url, repo_name)
        "#{git_url}/#{repo_name}"
      end

      def self.log_error(e)
        log_error = ([e.inspect]+backtrace_subset(e)).join("\n")
        @log.info("\n----------------error-----\n#{log_error}\n----------------error-----")
      end

      def self.backtrace_subset(e)
        e.backtrace[0..10]
      end

    end
  end
end