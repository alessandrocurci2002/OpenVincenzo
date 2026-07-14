#!/bin/bash

# Controlla che l'utente abbia passato un nome
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

xhost +local:root

sudo rm -rf /tmp/.docker.xauth
XAUTH=/tmp/.docker.xauth
touch $XAUTH
xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f $XAUTH nmerge -
chmod a+r $XAUTH

sudo docker run -it \
  --name=$CONTAINER_NAME \
  --env="DISPLAY=$DISPLAY" \
  --env="QT_X11_NO_MITSHM=1" \
  --env="XAUTHORITY=$XAUTH" \
  --env="GZ_IP=127.0.0.1" \
  --env="ROS_DOMAIN_ID=0" \
  --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
  --volume="$XAUTH:$XAUTH:rw" \
  --volume="$(pwd)/colcon_ws/src/open_vins:/root/colcon_ws/src/open_vins" \
  --volume="$(pwd)/depthai-ws:/root/depthai-ws" \
  --volume="$(pwd)/Makefile:/root/Makefile" \
  -v /dev:/dev \
  -v /sys:/sys \
  --device=/dev/bus/usb:/dev/bus/usb \
  --device-cgroup-rule='c 189:* rmw' \
  --net=host \
  --privileged \
  $IMAGE_NAME\
  