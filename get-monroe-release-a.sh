REL="-rela"
apt install -y apt-transport-https curl
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
echo 'deb [trusted=yes] https://raw.githubusercontent.com/MONROE-PROJECT/apt-repo/master stretch main' > /etc/apt/sources.list.d/monroe.list
apt update && apt install -y jq ssh libuv1 libjson-c3 libjq1 libonig4 dnsutils circle table-allocator-* monroe-experiment-core${REL} monroe-tap-agent${REL}
