#!/bin/bash
set -e

SCHEDID=$1
STATUS=$2

# Default variables
USERDIR="/experiments/user"
CONTAINER_NAME=monroe-$SCHEDID
NEAT_CONTAINER_NAME=monroe-neat-proxy
EXCLUDED_IF="Br|lo|metadata|wwan|ifb|docker"
OPINTERFACES="nlw_"
UNWANTED_TASKS_AT_EXPERIMENT_START=("docker pull" "rsync" "ansible" "ansible-wrapper" "apt" "scp")

URL_NEAT_PROXY=monroe/neat-proxy
NOERROR_CONTAINER_IS_RUNNING=0
ERROR_CONTAINER_DID_NOT_START=10
ERROR_NETWORK_CONTEXT_NOT_FOUND=11
ERROR_IMAGE_NOT_FOUND=12
ERROR_MAINTENANCE_MODE=13

# Update above default variables if needed 
. /etc/default/monroe-experiments

_EXPPATH=$USERDIR/$SCHEDID
_UPDATE_FIREWALL_="0"

echo -n "Checking for maintenance mode... "
MAINTENANCE=$(cat /monroe/maintenance/enabled 2>/dev/null|| echo 0)
if [ $MAINTENANCE -eq 1 ]; then
   echo 'failed; node is in maintenance mode.' > $_EXPPATH.status
   echo "enabled."
   exit $ERROR_MAINTENANCE_MODE
fi
echo "disabled."


if [ -f $_EXPPATH.conf ]; then
  CONFIG=$(cat $_EXPPATH.conf);
  IS_SSH=$(echo $CONFIG | jq -r '.ssh // empty');
  EDUROAM_IDENTITY=$(echo $CONFIG | jq -r '._eduroam.identity // empty');
  EDUROAM_HASH=$(echo $CONFIG | jq -r '._eduroam.hash // empty');
  IS_VM=$(echo $CONFIG | jq -r '.vm // empty');
  NEAT_PROXY=$(echo $CONFIG | jq -r '.neat // empty');
else
  echo "No config file found ($_EXPPATH.conf )" 
  exit $ERROR_IMAGE_NOT_FOUND
fi

exec &> >(tee -a $_EXPPATH/start.log) || {
   echo "Could not create log file $_EXPPATH/start.log"
   exit $ERROR_IMAGE_NOT_FOUND
}

echo -n "Ensure network and containers are set up... "
systemctl -q is-active monroe-namespace.service 2>/dev/null || {
  echo "Monroe Namespace is down"
  exit $ERROR_NETWORK_CONTEXT_NOT_FOUND
}

IMAGEID=$(docker images -q --no-trunc $CONTAINER_NAME)
if [ -z "$IMAGEID" ]; then
    echo "experiment container not found."
    exit $ERROR_IMAGE_NOT_FOUND;
fi

# check that this container is not running yet
if [ ! -z "$(docker ps | grep $CONTAINER_NAME)" ]; then
    echo "already running."
    exit $NOERROR_CONTAINER_IS_RUNNING;
fi

# check that this container name is not used
if [ ! -z "$(docker ps -a | grep $CONTAINER_NAME)" ]; then
    echo "already exists(stopped)."
    exit $ERROR_CONTAINER_DID_NOT_START;
fi

# Container boot counter and measurement UID

COUNT=$(cat $_EXPPATH.counter 2>/dev/null || echo 0)
COUNT=$(($COUNT + 1))
echo $COUNT > $_EXPPATH.counter

if [ -e /etc/nodeid.n2 ]; then
  NODEIDFILE="/etc/nodeid.n2"
elif [ -e /etc/nodeid ]; then 
  NODEIDFILE="/etc/nodeid"
else
  NODEIDFILE="/etc/hostname"
fi
NODEID=$(<$NODEIDFILE)

GUID="${IMAGEID}.${SCHEDID}.${NODEID}.${COUNT}"
# replace guid in the configuration

CONFIG=$(echo $CONFIG | jq '.guid="'$GUID'"|.nodeid="'$NODEID'"')
echo $CONFIG > $_EXPPATH.conf
echo "ok."

# setup eduroam if available

if [ ! -z "$EDUROAM_IDENTITY" ] && [ -x /usr/bin/eduroam-login.sh ] && [ ! -z "$EDUROAM_HASH" ]; then
    /usr/bin/eduroam-login.sh $EDUROAM_IDENTITY $EDUROAM_HASH
fi
# TODO: Error code if eduroam does not exist and robustify 

### PYCOM 
PYCOM_DIR="/dev/pycom"
MOUNT_PYCOM=""
if [ -x "/usr/bin/ykushcmd" ];then 
  # Power up all yepkit ports (assume pycom is only used for yepkit)"
  # TODO: detect if yepkit is there and optionally which port a pycom device is attached to
  echo "Power up all ports of the yepkit"
  for port in 1 2 3; do
    /usr/bin/ykushcmd -u $port || echo "Could not power up yepkit port : $port"
  done
  if  [ -x /usr/bin/factory-reset-pycom.py ]; then 
    echo -n "Waiting for $PYCOM_DIR: "
    timeout 30 bash -c -- "while [ ! -d $PYCOM_DIR ];do echo -n "."; sleep 1; done" || true
    echo " done, $(ls $PYCOM_DIR 2>/dev/null|wc -l) pycom devices found"
  fi
fi

# Reset pycom devices if they exist
if  [ -x /usr/bin/factory-reset-pycom.py ] && [ -d "$PYCOM_DIR" ]; then 
    echo "Trying to factory reset the board(s) (timeout 30 seconds per board)"
    for board in $(ls $PYCOM_DIR 2>/dev/null); do
      timeout 35 /usr/bin/factory-reset-pycom.py --device $PYCOM_DIR/$board --wait 30 --baudrate 115200 && {
        MOUNT_PYCOM="${MOUNT_PYCOM} --device $PYCOM_DIR/$board"
      } 
    done
fi
###

### NEAT PROXY #################################################
# Cleanup of old existing rules if any
set -- /etc/circle.d/60-*-neat-proxy.rules
if [ -f "$1" ]; then
    rm -f /etc/circle.d/60-*-neat-proxy.rules
    _UPDATE_FIREWALL_="1"
fi
## Stop the neat proxy container if any 
docker stop --time=10 $NEAT_CONTAINER_NAME 2>/dev/null || true

if [ ! -z "$NEAT_PROXY"  ] && [ -x /usr/bin/monroe-neat-init ]; then
  NEAT_PROXY_PATH=$_EXPPATH/neat-proxy/
  /usr/bin/monroe-neat-init $NEAT_PROXY_PATH
  _UPDATE_FIREWALL_="1"
fi
##################################################################

### Let modems rest for a while = idle period
MODEMS=$(ls /sys/class/net/ | egrep -v $EXCLUDED_IF | egrep $OPINTERFACES) || true
if [ ! -z "$MODEMS" ]; then   
  ## drop all network traffic for 30 seconds (idle period)
  # This line is to ensure that we do not kills the connection if the script is killed
  nohup /bin/bash -c 'sleep 35; circle start' > /dev/null &
  iptables -F
  iptables -P INPUT DROP
  iptables -P OUTPUT DROP
  iptables -P FORWARD DROP
  sleep 30
  _UPDATE_FIREWALL_="1"
fi
###

## Restart the firewall if needed
if [ "$_UPDATE_FIREWALL_" -eq "1" ];then 
  echo -n "Restarting firewall: "
  circle start
fi

### Stop tasks that can influence experiment results #####################
echo "Stopping unwanted tasks/processes before starting experiment..."
for task in "${UNWANTED_TASKS_AT_EXPERIMENT_START[@]}"; do
   echo -n "$task: "
   _PIDS=$(pgrep -f "$task" || true)
   if [ -z "$_PIDS" ]; then
        echo -n "not running"
   else
        echo -n "killing :"
   fi
   for _pid in $_PIDS; do
        /sbin/start-stop-daemon --stop --signal TERM --retry 30 --oknodo --pid $_pid && echo -n " $_pid"
   done
   echo ""
done

### START THE CONTAINER/VM ###############################################

echo -n "Starting container... "
if [ -d $_EXPPATH ]; then
    MOUNT_DISK="-v $_EXPPATH:/monroe/results -v $_EXPPATH:/outdir"
fi
if [ -d /experiments/monroe/tstat ]; then
    TSTAT_DISK="-v /experiments/monroe/tstat:/monroe/tstat:ro"
fi

if [ ! -z "$IS_SSH" ]; then
    OVERRIDE_ENTRYPOINT=" --entrypoint=dumb-init "
    OVERRIDE_PARAMETERS=" /bin/bash /usr/bin/monroe-sshtunnel-client.sh "
fi

cp /etc/resolv.conf $_EXPPATH/resolv.conf.tmp

if [ ! -z "$IS_VM" ] && [ -x /usr/bin/vm-deploy.sh ] && [ -x /usr/bin/vm-start.sh ]; then
    echo "Container is a vm, trying to deploy... "
    /usr/bin/vm-deploy.sh $SCHEDID
    echo -n "Copying vm config files..."
    VM_CONF_DIR=$_EXPPATH.confdir
    mkdir -p $VM_CONF_DIR
    cp $_EXPPATH/resolv.conf.tmp $VM_CONF_DIR/resolv.conf
    cp $_EXPPATH.conf $VM_CONF_DIR/config
    cp $NODEIDFILE $VM_CONF_DIR/nodeid
    cp /tmp/dnsmasq-servers-netns-monroe.conf $VM_CONF_DIR/dns
    echo "ok."

    echo "Starting VM... "
    # Kicking alive the vm specific stuff
    /usr/bin/vm-start.sh $SCHEDID $OVERRIDE_PARAMETERS
    echo "vm started." 
    CID=""
    PNAME="kvm"
    CONTAINER_TECHONOLOGY="vm"
    PID="$(cat $_EXPPATH.pid)" || true
else
    MONROE_NAMESPACE="$(docker ps --no-trunc -qf name=$MONROE_NAMESPACE_CONTAINER_NAME)"
    CID_ON_START=$(docker run -d $OVERRIDE_ENTRYPOINT  \
           --name=$CONTAINER_NAME \
           --net=container:$MONROE_NAMESPACE \
           --cap-add NET_ADMIN \
           --cap-add NET_RAW \
           --shm-size=1G \
           -v $_EXPPATH/resolv.conf.tmp:/etc/resolv.conf \
           -v $_EXPPATH.conf:/monroe/config:ro \
           -v ${NODEIDFILE}:/nodeid:ro \
           -v /tmp/dnsmasq-servers-netns-monroe.conf:/dns:ro \
           $MOUNT_PYCOM \
           $MOUNT_DISK \
           $TSTAT_DISK \
           $CONTAINER_NAME $OVERRIDE_PARAMETERS)
	  # CID: the runtime container ID
    echo "ok."
    CID=$(docker ps --no-trunc | grep "$CONTAINER_NAME" | awk '{print $1}' | head -n 1)
    PID=""
    PNAME="docker"
    CONTAINER_TECHONOLOGY="container"
    if [ ! -z "$CID" ]; then
      PID=$(docker inspect -f '{{.State.Pid}}' $CID) || true
      echo $PID > $_EXPPATH.pid
    fi
fi

if [ -x /usr/bin/usage-defaults ]; then 
  # start accounting
  echo "Starting accounting."
  /usr/bin/usage-defaults 2>/dev/null || true
fi

if [ ! -z "$PID" ]; then
  echo "Started $PNAME process $CID $PID."
else
  echo "failed; $CONTAINER_TECHONOLOGY exited immediately" > $_EXPPATH.status
  echo "$CONTAINER_TECHONOLOGY exited immediately."
  if [ -z "$IS_VM" ]; then
    echo "Log output:"
    docker logs -t $CID_ON_START || true
  fi
  exit $ERROR_CONTAINER_DID_NOT_START;  #Different exit code for VM?
fi

if [ -z "$STATUS" ]; then
  echo 'started' > $_EXPPATH.status
else
  echo $STATUS > $_EXPPATH.status
fi

[ -x /usr/bin/sysevent ] && sysevent -t Scheduling.Task.Started -k id -v $SCHEDID
echo "Startup finished $(date)."
