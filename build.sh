#!/bin/bash -e

VERSIONS="deb8 1ubuntu1"

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
UBUNTU_FIXES=0
for debian_version in $VERSIONS
do
    if [[ "$debian_version" == *"deb"* ]]
    then
        ignore="$ignore_files /etc/networkd-dispatcher"
    elif [[ "$debian_version" == *"ubuntu"* ]]
    then
        UBUNTU_FIXES=1
        ignore="$ignore_files /etc/network /etc/dhcp"
    else
        ignore=$ignore_files
    fi
    echo "Creating the deb package for $debian_version"
    echo "Source = $srcdir"
    echo "Destination = $outdir"
    echo "Ignoring these files and directories = $ignore"
    docker run --rm -e APPLY_UBUNTU_FIXES="$UBUNTU_FIXES" -e IGNORE_FILES_AND_DIR="$ignore" -e debian_version="$debian_version" $docker_args $build_container bash -c "/build.sh"
done
echo "Deleting temporarty build container : $build_container"
docker rmi --force $build_container &>/dev/null
