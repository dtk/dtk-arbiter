require 'grit'
module Arbiter
  module Common
    class GitClient
      def initialize(repo_dir,opts={})
        @repo_dir = repo_dir
        @grit_repo = (opts[:create] ? ::Grit::Repo.init(repo_dir) : ::Grit::Repo.new(repo_dir))
      end

      def clone_branch(remote_repo,branch,opts={})
        git_command__remote_add(remote_repo,branch)
        git_command__checkout(opts[:sha]||branch)
      end

      def pull_and_checkout_branch?(branch,opts={})
        sha = opts[:sha]
        #shortcut
        return if sha and (sha == current_branch_or_head())

        unless remote_branch_exists?(branch)
          git_command__remote_branch_add(branch)
          git_command__fetch()
        end

        if branch_exists?(branch)
          git_command__pull(branch)
          git_command__checkout(sha) if sha
        else
          git_command__checkout(sha||branch)
        end
      end

    private
      def git_command__remote_add(remote_repo,branch,remote_name=nil)
        remote_name ||= default_remote()
        git_command().remote(git_command_opts(),"add","-t", branch, "-f", remote_name, remote_repo)
      end

      def git_command__remote_branch_add(branch,remote_name=nil)
        remote_name ||= default_remote()
        git_command().remote(git_command_opts(),"set-branches", "--add", remote_name, branch)
      end

      def git_command__checkout(ref)
        unless current_branch_or_head() == ref
          git_command().checkout(git_command_opts(),ref)
        end
      end

      def git_command__fetch(remote_name=nil)
        remote_name ||= default_remote()
        git_command().fetch(git_command_opts(),remote_name)
      end

      def git_command__pull(branch,remote_name=nil)
        remote_name ||= default_remote()
        git_command().pull(git_command_opts(),remote_name,branch)
      end

      def branch_exists?(branch)
        @grit_repo.heads.find{|h|h.name == branch} ? true : nil
      end

      def remote_branch_exists?(branch,remote_name=nil)
        remote_name ||= default_remote()
        remote_branch = "#{remote_name}/#{branch}"
        @grit_repo.remotes.find{|h|h.name == remote_branch} ? true : nil
      end

      def current_branch_or_head()
        #this returns sha when detached head
        if @grit_repo.head
          @grit_repo.head.name
        elsif @grit_repo.commit('HEAD')
          @grit_repo.commit('HEAD').id
        end
      end

      def default_remote()
        'origin'
      end

      def git_command_opts(opts={})
        ret = {:raise => true, :timeout => 60}
        ret.merge!(:chdir => @repo_dir) unless opts[:no_chdir]
      end

      def git_command()
        @grit_repo.git
      end
    end
  end
end

