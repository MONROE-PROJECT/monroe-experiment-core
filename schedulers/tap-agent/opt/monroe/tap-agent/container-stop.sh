#!/bin/bash
#This script should always be run, as long as the container is deployed.

SCHEDID=$1
STATUS=$2

# Default variables
USERDIR="/experiments/user"
CONTAINER_NAME=monroe-$SCHEDID
USAGEDIR=/monroe/usage/netns
MNS="ip netns exec monroe"

NEAT_CONTAINER_NAME=monroe-neat-proxy
URL_NEAT_PROXY="monroe/neat-proxy"
NEAT_CG_DIR="/tmp/cgroupv2/neat-proxy"

# Update above default variables if needed
. /etc/default/monroe-experiments

_tmpfile_=/tmp/cleanup-$SCHEDID.log
_EXPPATH=$USERDIR/$SCHEDID

exec &> >(tee -a $_tmpfile_) || {
   echo "Could not create log file $_tmpfile_"
}

VTAPPREFIX=mvtap-
VM_TMP_FILE=/experiments/virtualization.rd/$SCHEDID.tar_dump
VM_OS_DISK=/var/lib/docker/scratch/virtualization/image-$SCHEDID.qcow2


if [ -f $_EXPPATH.conf ]; then
  CONFIG=$(cat $_EXPPATH.conf);
  STARTTIME=$(echo $CONFIG | jq -r '.start // empty');
  EDUROAM_IDENTITY=$(echo $CONFIG | jq -r '._eduroam.identity // empty');
  IS_VM=$(echo $CONFIG | jq -r '.vm // empty');
  NEAT_PROXY=$(echo $CONFIG | jq -r '.neat // empty');
fi
#TODO: STOP here?
_UPDATE_FIREWALL_="0"
[ -x /usr/bin/usage-defaults ] && {
  echo "Finalize accounting."
  /usr/bin/usage-defaults
}

if [ docker inspect $CONTAINER_NAME &>/dev/null ]; then
  echo -n "Stopping container... "
  if [ "$(docker inspect -f "{{.State.Running}}" $CONTAINER_NAME) &>/dev/null" == "true" ]; then
    docker stop --time=10 $CONTAINER_NAME
  fi
  echo "stopped:"
  docker inspect $CONTAINER_NAME|jq .[].State
  if [ -z "$STATUS" ]; then
    STATUS="finished"
  fi
elif [ -f $_EXPPATH.pid ]; then
  PID=$(cat $_EXPPATH.pid)
  if [ ! -z "$PID" ]; then
  	echo -n "Killing vm (if any)... "
  	kill -9 $PID &>/dev/null # Should be more graceful maybe
  	echo "ok."
  fi
fi


if [[ -f $VM_OS_DISK ]]; then # This file should always be here normaly
  echo -n "Deleting OS disk... "
  rm -f $VM_OS_DISK
  echo "ok."
fi

if [[ -f $VM_TMP_FILE ]]; then # This file should NOT be here normaly
  echo -n "Deleting ramdisk file... "
  rm -f $VM_TMP_FILE
  echo "ok."
fi

if [ -f $_EXPPATH.vmifhash ];then
  VMIFHASH="$(cat $_EXPPATH.vmifhash) 2>/dev/null" || true
  if [ ! -z "$VMIFHASH" ]; then
    VTAPS=$($MNS ls /sys/class/net/|grep "${VTAPPREFIX}${VMIFPREFIX}-") || true
    if [ ! -z "$VTAPS" ]; then
      echo -n "Deleting vtap interfaces in $MNS..."
      for IFNAME in $VTAPS; do
        echo -n "${IFNAME}..."
        $MNS ip link del ${IFNAME} || true
      done
      echo "ok."
    fi
  fi
fi

if [ -x "/usr/bin/ykushcmd" ];then
  # Power off yepkit (assume we use yepkit only for pycom)
  PYCOM_DIR="/dev/pycom"
  if [ -d "$PYCOM_DIR" ]; then
    for port in 1 2 3; do
        /usr/bin/ykushcmd -d $port || echo "Could not down yepkit port : $port"
    done
  fi
fi

## Disable NEAT proxy ###
if [ ! -z "$NEAT_PROXY"  ] && [ -x /usr/bin/monroe-neat-init ]; then # If this is a experiment using the neat-proxy
  rm -f /etc/circle.d/60-*-neat-proxy.rules
  _UPDATE_FIREWALL_="1"
  ## Stop the neat proxy container
  docker stop $NEAT_CONTAINER_NAME || echo "Could not stop $NEAT_CONTAINER_NAME"
  docker rm -f $NEAT_CONTAINER_NAME || echo "Could not remove $NEAT_CONTAINER_NAME"
  umount ${NEAT_CG_DIR} &>/dev/null || echo "Could not umount ${NEAT_CG_DIR}"
  rm -rf ${NEAT_CG_DIR} &>/dev/null
fi

echo -n "Syncing traffic statistics... "
TRAFFIC=$(cat $_EXPPATH.traffic)

# Will only exist if /usr/bin/usage has been running
if [ -d $USAGEDIR/$SCHEDID ];then
  for i in $(ls $USAGEDIR/$SCHEDID/*.rx.total|sort); do
    MACICCID=$(basename $i | sed -e 's/\..*//g')
    TRAFFIC=$(echo "$TRAFFIC" | jq ".interfaces.\"$MACICCID\"=$(cat $USAGEDIR/$SCHEDID/$MACICCID.total)")
  done
  rm -rf  $USAGEDIR/$SCHEDID #Accounting (if exists)
fi

if [ ! -z "$TRAFFIC" ]; then
  echo "$TRAFFIC" > $_EXPPATH.traffic
  echo "$TRAFFIC" > $_EXPPATH/container.stat
fi
echo "ok."

#TODO: Make this dynamic to not hardcode to wlan0
EDUROAM_PID="$(pgrep -f /sbin/wpa_supplicant 2>/dev/null)"
if [ ! -z "$EDUROAM_IDENTITY" ] && \
   [ -x /usr/bin/eduroam-login.sh ] && \
   [ ! -z "$EDUROAM_PID" ] && \
   [ -z "$(ip link |grep wlan0:)"];then
    echo -n "Deleting EDUROAM credentials... "ß
    rm /etc/wpa_supplicant/wpa_supplicant.eduroam.conf
    kill -9 $EDUROAM_PID
    iwconfig wlan0 ap 00:00:00:00:00:00
    ifconfig wlan0 0.0.0.0 down
    echo "ok."
fi
## Retrive Kernel Logs
if [ ! -z "$STARTTIME" ]; then
  # TODO : USe docker inspect to get time when container was running
  echo "Retrieving dmesg events:"
  dmesg|awk '{time=0 + substr($1,2,length($1)-2); if (time > '$STARTTIME') print $0}'
  echo ""
fi

[ -x /usr/bin/sysevent ] && sysevent -t Scheduling.Task.Stopped -k id -v $SCHEDID

cat $_tmpfile_ > $_EXPPATH/cleanup.log
echo "(end of public log)"

## Cleanup
echo -n "Deleting container image... "
REF=$( docker images | grep $CONTAINER_NAME | awk '{print $3}' )
if [ -z "$REF" ]; then
  echo "Container is no longer deployed.";
else
  docker rmi -f $CONTAINER_NAME
fi
echo "ok."


##WEBGUI status codes
if [ -z "$STATUS" ]; then
  echo 'stopped' > $_EXPPATH.status;
else
  echo $STATUS > $_EXPPATH.status;
fi

#Signal to sync script that it can clean the folders (when synched)
touch $_EXPPATH.stopped

if [ -x /usr/bin/modems ]; then
  echo -n "Resetting modem state: "
  for ip4table in $(modems|jq .[].ip4table); do
    curl -s -X POST http://localhost:88/modems/${ip4table}/usbreset
  done
  echo "done"
fi
echo "ok."
if [ "$_UPDATE_FIREWALL_" -eq "1" ];then
  echo -n "Restarting firewall: "
  circle start
fi

echo "Cleanup finished $(date)."
