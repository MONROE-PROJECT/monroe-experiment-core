#!/bin/bash -e

# Author: Jonas Karlsson <jonas.karlsson@kau.se>
# Date: April 2019
# License: GNU General Public License v3

function abspath {
    echo $(cd "$1" && pwd)
}

build_container=$RANDOM

srcdir=$(abspath "$1")
outdir=$(abspath "$2")
ignore_files="Dockerfile *.deb build.sh"

echo "Building the build container for $(basename $srcdir)"
docker pull debian:stretch >/dev/null
docker build --rm -t $build_container  . >/dev/null && echo "Finished building $build_container" 

# Set the paths and current UID and GID to container (to set correct output permissions)
docker_args="-i -v $srcdir:/source-ro:ro -v $outdir:/output -e USER=$(id -u) -e GROUP=$(id -g)"

echo "Creating the deb package"
echo "Source = $srcdir"
echo "Destination = $outdir"
echo "Ignoring these files = $ignore_files"
docker run --rm -e IGNORE_FILES="$ignore_files" $docker_args $build_container bash -c "/build.sh"

echo "Deleteing temporarty build container : $build_container"
docker rmi --force $CONTAINER &>/dev/null
