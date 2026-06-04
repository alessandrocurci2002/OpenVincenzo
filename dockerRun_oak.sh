#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Use: ./dockerRun_oak.sh <container_name> <image_name> [command...]"
  exit 1
fi

CONTAINER_NAME=$1
IMAGE_NAME=$2
shift 2

if command -v xhost >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xhost +local:root >/dev/null 2>&1 || true
fi

XAUTH=/tmp/.docker.xauth
rm -f "$XAUTH"
touch "$XAUTH"
if command -v xauth >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge - >/dev/null 2>&1 || true
fi
chmod a+r "$XAUTH"

DOCKER_CMD=("${DOCKER_BIN:-docker}")
if ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
  DOCKER_CMD=(sudo docker)
fi

DOCKER_ARGS=(
  -it
  --name="$CONTAINER_NAME"
  --env="DISPLAY=${DISPLAY:-}"
  --env="QT_X11_NO_MITSHM=1"
  --env="XAUTHORITY=$XAUTH"
  --env="GZ_IP=127.0.0.1"
  --env="ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}"
  --env="RUN_PX4_SETUP=${RUN_PX4_SETUP:-1}"
  --env="BUILD_OPENVINS=${BUILD_OPENVINS:-1}"
  --env="OAK_LAUNCH_FILE=${OAK_LAUNCH_FILE:-}"
  --env="OAK_BOOT_SECONDS=${OAK_BOOT_SECONDS:-10}"
  --volume="$XAUTH:$XAUTH:rw"
  --volume="$(pwd)/PX4-Autopilot:/root/PX4-Autopilot"
  --volume="$(pwd)/colcon_ws/src/open_vins:/root/colcon_ws/src/open_vins"
  --volume="/dev/bus/usb:/dev/bus/usb"
  --device-cgroup-rule="c 189:* rmw"
  --net=host
  --privileged
)

if [ -d /tmp/.X11-unix ]; then
  DOCKER_ARGS+=(--volume="/tmp/.X11-unix:/tmp/.X11-unix:rw")
fi

if [ -d /run/udev ]; then
  DOCKER_ARGS+=(--volume="/run/udev:/run/udev:ro")
fi

if [ -d /dev/dri ]; then
  DOCKER_ARGS+=(--device=/dev/dri)
fi

"${DOCKER_CMD[@]}" run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "$@"
