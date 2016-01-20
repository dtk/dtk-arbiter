#!/usr/bin/env bash

## usage:
#  ./update.sh [branch]

# get script directory, i.e. dtk-arbiter root
base_dir="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# make sure puppet-omnibus is first in path
export PATH=/opt/puppet-omnibus/embedded/bin/:${PATH}
# default branch to stable
branch=${1:-stable}

cd ${base_dir}
git fetch
if git rev-parse --verify origin/${branch}; then
  git reset --hard origin/${branch}
  bundle install
else
  echo "Branch ${branch} doesn't seem to exist. Aborting upgrade"
  exit 1
fi