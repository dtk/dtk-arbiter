#!/usr/bin/env bash


if [[ ! `command -v docker` ]]; then
  echo -e "Cannot find the 'docker' executable\nPlease make sure it's installed before running the garbage collector"
  exit 1
fi

# set gc image and parameters
# dtk/docker-gc is a rebuild of spotify/docker-gc
docker_gc_image='getdtk/docker-gc'
docker_gc_schedule='1d'
docker_gc_grace_period='86400'

docker pull ${docker_gc_image}
docker run --rm -e GRACE_PERIOD_SECONDS=${docker_gc_grace_period} -e FORCE_IMAGE_REMOVAL=1 -v /var/run/docker.sock:/var/run/docker.sock -v /etc:/etc ${docker_gc_image}