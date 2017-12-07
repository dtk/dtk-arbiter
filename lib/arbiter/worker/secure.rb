module DTK::Arbiter
  class Worker
    class Secure < self
      SSH_AUTH_KEYS_FILE_NAME = "authorized_keys"

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end
      private :initialize

      def process
        # temporary fix for authorize node
        sleep 1

        return notify_of_error("System Worker needs action name to proceed, aborting processing!", :missing_params) unless action_name
        return notify_of_error(ErrorFormatter.action_not_defined(action_name, self), :missing_params) unless self.respond_to?(action_name)

        results = self.send(action_name)
        notify(results)
      end

      def grant_access
        check_required!(:rsa_pub_key, :rsa_pub_name, :system_user)

        ret = {}

        if does_user_exist?(get(:system_user))
          puppet_params = {
              :name => get(:rsa_pub_name),
              :ensure => 'present',
              :key => normalize_rsa_pub_key(get(:rsa_pub_key)),
              :type => 'ssh-rsa',
              :user => get(:system_user)
            }

          Utils::PuppetRunner.execute(:ssh_authorized_key, puppet_params)

          # There is a bug where we are expiriencing issues with above changes not taking effect for no apperent reason
          # if detected we repeat puppet apply

          unless key_added?(puppet_params[:user], puppet_params[:key])
            Log.info("Fallback, repeating SSH access grant")
            Utils::PuppetRunner.execute(:ssh_authorized_key, puppet_params)
          end

          raise ActionAbort, "We were not able to add SSH access for given node (PuppetError)" unless key_added?(puppet_params[:user], puppet_params[:key])

          ret = { :message => "Access to system user '#{get(:system_user)}' has been granted for '#{get(:rsa_pub_name)}'" }
        else
          raise ActionAbort, "System user '#{get(:system_user)}' not found on given node"
        end

        success_response(ret)
      end

      def revoke_access
        check_required!(:rsa_pub_name, :system_user)
        ret = {}

        if does_user_exist?(get(:system_user))
          Utils::PuppetRunner.execute(
            :ssh_authorized_key,
            {
              :name => get(:rsa_pub_name),
              :ensure => 'absent',
              :type => 'ssh-rsa',
              :user => get(:system_user)
           }
          )

          ret = { :message => "Access for system user '#{get(:system_user)}' has been revoked" }
        else
          raise ActionAbort, "System user '#{get(:system_user)}' not found on given node"
        end

        success_response(ret)
      end


      def add_rsa_info
        check_required!(:agent_ssh_key_public, :agent_ssh_key_private, :server_ssh_rsa_fingerprint)

        ssh_folder_path = '/root/.ssh'
        rsa_path     = "#{ssh_folder_path}/id_rsa"
        rsa_pub_path = "#{ssh_folder_path}/id_rsa.pub"
        known_hosts  = "#{ssh_folder_path}/known_hosts"

        # create private rsa file if needed
        unless donot_create_file?(:private, rsa_path, get(:agent_ssh_key_private))
          File.open(rsa_path, "w" , 0600){ |f| f.print get(:agent_ssh_key_private) }
        end

        # create public rsa file if needed
        unless donot_create_file?(:public, rsa_pub_path, get(:agent_ssh_key_public))
          File.open(rsa_pub_path, "w"){ |f| f.print get(:agent_ssh_key_public) }
        end

        # add rsa_fingerprint to known hsots; server logic makes sure that is not get added twice so no duplicates
        File.open(known_hosts, "a" ){ |f| f.print get(:server_ssh_rsa_fingerprint) }

        success_response
      end

    private

      def donot_create_file?(type, path, content)
        # raises exception if these files already exists and content differs
        if File.exists?(path)
          existing = File.open(path).read

          if existing == content
            true
          else
            raise InvalidContent, "RSA #{type} key already exists and differs from one in payload"
          end
        end
      end

      def does_user_exist?(system_user)
        !File.open('/etc/passwd').grep(/^#{system_user}:/).empty?
      end

      def key_added?(system_user, pub_key)
        if system_user == "root"
          results = `more /#{system_user}/.ssh/#{SSH_AUTH_KEYS_FILE_NAME} | grep #{pub_key}`
        else
          results = `more /home/#{system_user}/.ssh/#{SSH_AUTH_KEYS_FILE_NAME} | grep #{pub_key}`
        end
        !results.empty?
      end

      def normalize_rsa_pub_key(rsa_pub_key)
        rsa_pub_key.strip!
        rsa_pub_key.gsub!(/.* (.*) .*/,'\1')
        rsa_pub_key
      end

    end
  end
end
