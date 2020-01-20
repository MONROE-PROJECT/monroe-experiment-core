FROM debian:stretch

MAINTAINER Jonas.Karlsson@kau.se

#APT OPTS
ENV APT_OPTS -y --allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends --no-install-suggests --allow-unauthenticated

RUN sed -i -e 's/main/main non-free/g' /etc/apt/sources.list
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update
RUN apt-get ${APT_OPTS} install \
    python3-pip \
    fakeroot

#If we have written something in python3.6 syntax, ie fstrings
RUN pip3 install f2format

# Used to add extra commands neded be executed before build
RUN echo 'mkdir -p /source/' >> /prebuild.sh
RUN echo 'cp -a /source-ro/* /source' >> /prebuild.sh
RUN echo 'for f in ${IGNORE_FILES_AND_DIR}; do rm -rf /source/$f ; done' >> prebuild.sh
RUN echo 'sed -i s/##DEBIAN_VERSION##/${debian_version}/g /source/DEBIAN/control' >> prebuild.sh
RUN echo 'usr/local/bin/f2format -n /source/' >> /prebuild.sh
RUN chmod +x /prebuild.sh

RUN echo '/prebuild.sh' >> /build.sh
RUN echo '/usr/bin/fakeroot /usr/bin/dpkg-deb --build /source /output/' >> /build.sh
RUN chmod +x /build.sh
