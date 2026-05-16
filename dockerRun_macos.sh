#!/bin/bash

if [ -z "$1" ]; then
  echo "Use: ./start_ros.sh <container_name> <image_name>"
  exit 1
fi
CONTAINER_NAME=$1

if [ -z "$2" ]; then
  echo "Use: ./start_ros.sh <container_name> <image_name>"
  exit 1
fi
IMAGE_NAME=$2

# XQuartz deve essere aperto prima
open -a XQuartz
sleep 2

xhost +localhost

XAUTH=/tmp/.docker.xauth
rm -rf $XAUTH
touch $XAUTH
xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f $XAUTH nmerge -
chmod a+r $XAUTH

docker run -it \
  -p 18570:18570/udp \
  --name=$CONTAINER_NAME \
  --env="DISPLAY=host.docker.internal:0" \
  --env="QT_X11_NO_MITSHM=1" \
  --env="XAUTHORITY=$XAUTH" \
  --env="GZ_IP=127.0.0.1" \
  --env="ROS_DOMAIN_ID=0" \
  --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
  --volume="$XAUTH:$XAUTH:rw" \
  --privileged \
  $IMAGE_NAME \
  bash