#!/usr/bin/env bash

. /host_volume/dtk.config

# Make sure ssh directory exists on mounted volume
mkdir -p /host_volume/ssh
# Persist RSA keys recieved from Host tenant 
ln -sf /host_volume/ssh/tenant/id_rsa /root/.ssh/

# Persist puppet modules dir
mkdir -p /host_volume/modules
if [[ ! -L /usr/share/dtk/modules ]]; then
  mv /usr/share/dtk/modules/* /host_volume/modules/
  rm -rf /usr/share/dtk/modules/
  ln -sf /host_volume/modules /usr/share/dtk/
fi

# Set defaults
GIT_PORT=${GIT_PORT-2222}
if [[ -z $GIT_USERNAME ]]; then
  GIT_USERNAME=dtk1
fi
PBUILDERID=${PBUILDERID-docker-executor}
PRIVATE_KEY_NAME=${PRIVATE_KEY_NAME-arbiter_remote}
STOMP_USERNAME=${STOMP_USERNAME-dtk1}
STOMP_PASSWORD=${STOMP_PASSWORD-marionette}
STOMP_PORT=${STOMP_PORT-6163}

if [[ "$SKIP_CONFIG" != true ]]; then
cat << EOF > /etc/dtk/arbiter.cfg
stomp_url = ${PUBLIC_ADDRESS}
stomp_port = ${STOMP_PORT}
stomp_username = ${STOMP_USERNAME}
stomp_password = ${STOMP_PASSWORD}
arbiter_topic = /topic/arbiter.${STOMP_USERNAME}.broadcast
arbiter_queue = /queue/arbiter.${STOMP_USERNAME}.reply
git_server = "ssh://${GIT_USERNAME}@${PUBLIC_ADDRESS}:${GIT_PORT}"
pbuilderid = ${PBUILDERID}
private_key = /host_volume/arbiter/arbiter_remote
EOF
fi

# Make sure knonw_hosts is set up correctly
ssh-keyscan -p ${GIT_PORT} -H ${PUBLIC_ADDRESS} > /tmp/ssh_host.tmp
host_key=$(head -1 /tmp/ssh_host.tmp | awk '{print $3}')
if ! grep -q "$host_key" ~/.ssh/known_hosts >/dev/null 2>&1; then 
  cat /tmp/ssh_host.tmp >> ~/.ssh/known_hosts
fi
rm /tmp/ssh_host.tmp

/opt/puppet-omnibus/embedded/bin/ruby start.rb --foreground
