#!/bin/bash -e

function abspath {
    echo $(cd "$1" && pwd)
}

srcdir=$(abspath "$1")
outdir=$(abspath "$2")

if [[ -x "$srcdir/build.sh" && "$PWD" != "$srcdir" ]]
then
    echo "We have a local build file for this component use that"
    cd $srcdir
    ./build.sh $srcdir $outdir
    exit $?
fi

echo "Using global build file to build $(basename $srcdir)"
build_container=$RANDOM
ignore_files="Dockerfile *.deb build.sh *.md"

echo "Building the global build container"
docker pull debian:stretch >/dev/null
docker build --rm -t $build_container  . >/dev/null && echo "Finished building $build_container"

# Set the paths and current UID and GID to container (to set correct output permissions)
docker_args="-i -v $srcdir:/source-ro:ro -v $outdir:/output -e USER=$(id -u) -e GROUP=$(id -g)"

echo "Creating the deb package"
echo "Source = $srcdir"
echo "Destination = $outdir"
echo "Ignoring these files = $ignore_files"
docker run --rm -e IGNORE_FILES="$ignore_files" $docker_args $build_container bash -c "/build.sh"

echo "Deleting temporarty build container : $build_container"
docker rmi --force $CONTAINER &>/dev/null
