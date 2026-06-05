#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Use: ./dockerRun.sh <container_name> <image_name> [command...]"
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
  --env="FORCE_BUILD_OPENVINS=${FORCE_BUILD_OPENVINS:-0}"
  --env="RUN_ROS_GZ_BRIDGES=${RUN_ROS_GZ_BRIDGES:-0}"
  --env="GZ_BRIDGE_STREAMS=${GZ_BRIDGE_STREAMS:-left,right,imu}"
  --env="GZ_MODEL_NAME=${GZ_MODEL_NAME:-x500_depth_0}"
  --volume="$XAUTH:$XAUTH:rw"
  --volume="$(pwd)/.git:/root/.git:ro"
  --volume="$(pwd)/PX4-Autopilot:/root/PX4-Autopilot"
  --volume="$(pwd)/colcon_ws/src/open_vins:/root/colcon_ws/src/open_vins"
  --volume="${OPENVINCENZO_COLCON_BUILD_VOLUME:-openvincenzo_colcon_build}:/root/colcon_ws/build"
  --volume="${OPENVINCENZO_COLCON_INSTALL_VOLUME:-openvincenzo_colcon_install}:/root/colcon_ws/install"
  --volume="${OPENVINCENZO_COLCON_LOG_VOLUME:-openvincenzo_colcon_log}:/root/colcon_ws/log"
  --net=host
  --privileged
)

if [ -d /tmp/.X11-unix ]; then
  DOCKER_ARGS+=(--volume="/tmp/.X11-unix:/tmp/.X11-unix:rw")
fi

if [ -d /dev/dri ]; then
  DOCKER_ARGS+=(--device=/dev/dri)
fi

"${DOCKER_CMD[@]}" run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "$@"
