#!/bin/bash
set -e

SCHEDID=$1
ASYNC=$2

# Default variables
USERDIR="/experiments/user"
CHECK_STORAGE_QUOTA=0

# TODO: set in status file 
CONTAINER_NAME=monroe-$SCHEDID

ERROR_CONTAINER_NOT_FOUND=100
ERROR_INSUFFICIENT_DISK_SPACE=101
ERROR_QUOTA_EXCEEDED=102
ERROR_MAINTENANCE_MODE=103
ERROR_CONTAINER_DOWNLOADING=104
ERROR_EXPERIMENT_IN_PROGRESS=105

# Update above default variables if needed 
. /etc/default/monroe-experiments

_tmpfile_=/tmp/container-deploy.$SCHEDID

_EXPPATH=$USERDIR/$SCHEDID

if [ -z "$ASYNC" ]; then
  ASYNC=1
elif [ "$ASYNC" != "1" ]; then
  ASYNC=0
fi

echo "redirecting all output to the following locations:"
echo " - $_tmpfile_ until an experiment directory is created"
echo " - experiment/deploy.log after that."

exec &> >(tee -a $_tmpfile_)

echo "Running asynchronously: $ASYNC"
echo -n "Checking for maintenance mode... "
MAINTENANCE=$(cat /monroe/maintenance/enabled 2>/dev/null || echo 0)
if [ $MAINTENANCE -eq 1 ]; then
  echo "enabled."
  exit $ERROR_MAINTENANCE_MODE;
fi
echo "disabled."

echo -n "Checking for running experiments... "
RUNNING_EXPERIMENTS=$(/usr/bin/experiments || true )
if [ ! -z "$RUNNING_EXPERIMENTS" ]; then
   echo "experiment : $RUNNING_EXPERIMENTS is running, abort"
   exit $ERROR_EXPERIMENT_IN_PROGRESS
fi
echo "ok."

# Check if we have sufficient resources to deploy this container.
# If not, return an error code to delay deployment.

if [ -f $_EXPPATH.conf ]; then
  CONFIG=$(cat $_EXPPATH.conf)
  QUOTA_DISK=$(echo $CONFIG | jq -r '.storage // 10000000')
  CONTAINER_URL=$(echo $CONFIG | jq -r .script)
else
  echo "No config file found ($_EXPPATH.conf )"
  exit $ERROR_CONTAINER_NOT_FOUND
fi

QUOTA_DISK_KB=$(( $QUOTA_DISK / 1000 ))

echo -n "Checking for (container) disk space... "
DISKSPACE=$(df /var/lib/docker --output=avail|tail -n1)
if (( "$DISKSPACE" < $(( 100000 + $QUOTA_DISK_KB )) )); then
    exit $ERROR_INSUFFICIENT_DISK_SPACE;
fi
echo "ok."

echo -n "Checking if a deployment is ongoing... "
DEPLOYMENT=$(ps ax|grep docker|grep pull) || true
if [ -z "$DEPLOYMENT" ]; then
  echo "no."

  if [ -z "$(iptables-save | grep -- '-A OUTPUT -p tcp -m tcp --dport 443 -m owner --gid-owner 0 -j ACCEPT')" ]; then
    iptables -w -I OUTPUT 1 -p tcp --destination-port 443 -m owner --gid-owner 0 -j ACCEPT
    iptables -w -Z OUTPUT 1
    iptables -w -I INPUT 1 -p tcp --source-port 443 -j ACCEPT
    iptables -w -Z INPUT 1
  fi
elif [[ "$DEPLOYMENT" == *"$CONTAINER_URL"* ]]; then
  echo "yes, this container is being loaded in the background"
  #TODO : Should we exit here?
else
  echo "yes, delaying the download"
  exit $ERROR_CONTAINER_DOWNLOADING
fi

# FIXME: quota monitoring does not work with a background process
[ -x /usr/bin/sysevent ] && /usr/bin/sysevent -t Scheduling.Task.Deploying -k id -v $SCHEDID

echo -n "Pulling container..."
# try for 30 minutes to pull the container, send to background
timeout 1800 docker pull $CONTAINER_URL &
PROC_ID=$!

# check results every 10 seconds for 60 seconds, or continue next time
# TODO: Clearify What is next time/what calls this script again ?
_LOOPCOUNT=1
while [ "$_LOOPCOUNT" -le 6 ]; do 
  sleep 10
  if kill -0 "$PROC_ID" >/dev/null 2>&1; then
    echo -n "."
    if [ "$ASYNC" -eq 1 ]; then
      _LOOPCOUNT=$((_LOOPCOUNT+1))
    fi
    continue
  fi
  break
done

if [ "$ASYNC" -eq 1 ] && kill -0 "$PROC_ID" >/dev/null 2>&1; then
  echo -n ". delayed; continuing in background."
  exit $ERROR_CONTAINER_DOWNLOADING
fi

# the download finished. Do accounting and clear iptables rules
if [ ! -z "$(iptables-save | grep -- '-A OUTPUT -p tcp -m tcp --dport 443 -m owner --gid-owner 0 -j ACCEPT')" ]; then
  SENT=$(iptables -vxL OUTPUT 1 | awk '{print $2}')
  RECEIVED=$(iptables -vxL INPUT 1 | awk '{print $2}')
  SUM=$(($SENT + $RECEIVED))

  iptables -w -D OUTPUT -p tcp --destination-port 443 -m owner --gid-owner 0 -j ACCEPT   || true
  iptables -w -D INPUT  -p tcp --source-port 443 -j ACCEPT                               || true
else
  echo "debug: could not find acounting rule"
  iptables-save | grep 443 || true
  # TODO: SHould we exit here?
fi

#This prevent the rest of the script to fail
if [ -z "$SUM" ];then
  echo "Storage counting failed, SUM == 0"
  SUM=0
fi

# these two are acceptable:
# exit code 0   = successful wait
# exit code 127 = PID does not exist anymore.

wait $PROC_ID || {
  EXIT_CODE=$?
  echo "exit code $EXIT_CODE"
  if [ $EXIT_CODE -ne 127 ]; then
      exit $ERROR_CONTAINER_NOT_FOUND
  fi
}

#retag container image with scheduling id and remove the URL tag
docker tag $CONTAINER_URL $CONTAINER_NAME
docker rmi $CONTAINER_URL

# check if storage quota is exceeded - should never happen
if [ "$CHECK_STORAGE_QUOTA" -eq "1" ] && [ "$SUM" -gt "$QUOTA_DISK" ]; then
  docker rmi $CONTAINER_NAME || true
  echo  "quota exceeded ($SUM)."
  exit $ERROR_QUOTA_EXCEEDED;
fi

JSON=$( echo '{}' | jq .deployment=$SUM )
echo $JSON > $_EXPPATH.traffic

echo  "ok."  # Pulling container

echo -n "Creating file system... "
if [ ! -d $_EXPPATH ]; then
    mkdir -p $_EXPPATH
    dd if=/dev/zero of=$_EXPPATH.disk bs=1000 count=$QUOTA_DISK_KB
    mkfs.ext4 $_EXPPATH.disk -F -L $SCHEDID
fi
mountpoint -q $_EXPPATH || {
    mount -t ext4 -o loop,data=journal,nodelalloc,barrier=1 $_EXPPATH.disk $_EXPPATH
}
echo "ok."

echo "Deployment finished $(date)".
[ -x /usr/bin/sysevent ] && /usr/bin/sysevent -t Scheduling.Task.Deployed -k id -v $SCHEDID
# moving deployment files and switching redirects
cat $_tmpfile_ >> $_EXPPATH/deploy.log
rm -f $_tmpfile_
