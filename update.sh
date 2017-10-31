#!/usr/bin/env bash

## usage:
#  ./update.sh [branch]

# get script directory, i.e. dtk-arbiter root
base_dir="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# make sure puppet-omnibus is first in path
export PATH=/opt/puppet-omnibus/embedded/bin/:${PATH}
arbiter_cfg='/etc/dtk/arbiter.cfg'
# default branch to stable
branch=${1:-stable}

# try to pick up the arbiter branch from arbiter.cfg
arbiter_update=$(grep '^arbiter_update' /etc/dtk/arbiter.cfg | cut -d= -f2 | tr -d ' ') 
if [[ -s $arbiter_cfg ]] && [[ -z "$1" ]] && [[ "$arbiter_update" == 'true' ]]; then
  branch_cfg=$(grep '^arbiter_branch' /etc/dtk/arbiter.cfg | cut -d= -f2 | tr -d ' ')
fi
[[ -n "$branch_cfg" ]] && branch=$branch_cfg

cd ${base_dir}
git fetch
if git rev-parse --verify origin/${branch}; then
  git reset --hard origin/${branch}
  bundle install
else
  echo "Branch ${branch} doesn't seem to exist. Aborting upgrade"
  exit 1
fi