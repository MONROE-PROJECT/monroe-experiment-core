# Author: Jonas Karlsson <jonas.karlsson@kau.se>
# Date: April 2019
# License: GNU General Public License v3 

FROM debian:stretch
MAINTAINER jonas.Karlsson@kau.se

#APT OPTS
ENV APT_OPTS -y --allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends --no-install-suggests --allow-unauthenticated

ADD https://get.docker.com /get-docker.sh

RUN sed -i -e 's/main/main non-free/g' /etc/apt/sources.list
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update 
RUN apt-get ${APT_OPTS} install \
    fakeroot

RUN sh /get-docker.sh

# Used to add extra commands neded be executed before build
RUN echo 'set -e' >> /prebuild.sh
RUN echo 'mkdir -p /source/' >> /prebuild.sh
RUN echo 'cp -a /source-ro/* /source' >> /prebuild.sh
RUN echo 'for f in ${IGNORE_FILES}; do rm -f /source/$f ; done' >> prebuild.sh
RUN echo 'HASH=$(cat /source/DEBIAN/control|grep Version|cut -f2 -d " ")' >> prebuild.sh
RUN echo '/usr/bin/docker pull monroe/base@sha256:$HASH >/dev/null' >> prebuild.sh
RUN echo '/usr/bin/docker tag monroe/base@sha256:$HASH monroe/base:complete' >> prebuild.sh
RUN echo '/usr/bin/docker save -o /source/tmp/monroe-base.tar monroe/base:complete' >> prebuild.sh
RUN chmod +x /prebuild.sh

RUN echo '/prebuild.sh' >> /build.sh
RUN echo '/usr/bin/fakeroot /usr/bin/dpkg-deb --build /source /output/' >> /build.sh
RUN chmod +x /build.sh

