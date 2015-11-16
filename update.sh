#!/usr/bin/env bash

# get script directory, i.e. dtk-arbiter root
base_dir="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# make sure puppet-omnibus is first in path
export PATH=/opt/puppet-omnibus/embedded/bin/:${PATH}

cd ${base_dir}
# reset everything just in case and then pull
git fetch
git reset --hard origin/stable

bundle install