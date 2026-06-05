#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
PX4_GZ_WORLD="${PX4_GZ_WORLD:-baylands}"
GZ_MODEL_NAME="${GZ_MODEL_NAME:-x500_depth_0}"
GZ_CAMERA_LINK="${GZ_CAMERA_LINK:-camera_link}"
GZ_BASE_LINK="${GZ_BASE_LINK:-base_link}"
GZ_LEFT_CAMERA_SENSOR="${GZ_LEFT_CAMERA_SENSOR:-left_camera}"
GZ_RIGHT_CAMERA_SENSOR="${GZ_RIGHT_CAMERA_SENSOR:-right_camera}"
GZ_RGB_CAMERA_SENSOR="${GZ_RGB_CAMERA_SENSOR:-IMX214}"
GZ_IMU_SENSOR="${GZ_IMU_SENSOR:-imu_sensor}"
GZ_BRIDGE_STREAMS="${GZ_BRIDGE_STREAMS:-left,right,imu}"
GZ_BRIDGE_WAIT_SECONDS="${GZ_BRIDGE_WAIT_SECONDS:-180}"

ROS_LEFT_IMAGE_TOPIC="${ROS_LEFT_IMAGE_TOPIC:-/cam0/image_raw}"
ROS_RIGHT_IMAGE_TOPIC="${ROS_RIGHT_IMAGE_TOPIC:-/cam1/image_raw}"
ROS_RGB_IMAGE_TOPIC="${ROS_RGB_IMAGE_TOPIC:-/rgb/image_raw}"
ROS_IMU_TOPIC="${ROS_IMU_TOPIC:-/imu0}"

source_setup() {
  set +u
  source "$1"
  set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"

camera_topic() {
  local sensor="$1"
  printf "/world/%s/model/%s/link/%s/sensor/%s/image" \
    "${PX4_GZ_WORLD}" "${GZ_MODEL_NAME}" "${GZ_CAMERA_LINK}" "${sensor}"
}

imu_topic() {
  printf "/world/%s/model/%s/link/%s/sensor/%s/imu" \
    "${PX4_GZ_WORLD}" "${GZ_MODEL_NAME}" "${GZ_BASE_LINK}" "${GZ_IMU_SENSOR}"
}

available_topics() {
  gz topic -l 2>/dev/null || true
}

wait_for_topic() {
  local topic="$1"
  local waited=0

  while (( waited <= GZ_BRIDGE_WAIT_SECONDS )); do
    if available_topics | grep -Fxq "${topic}"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  echo "Gazebo topic not found after ${GZ_BRIDGE_WAIT_SECONDS}s: ${topic}" >&2
  echo "Available camera/IMU topics:" >&2
  available_topics | grep -Ei "camera|image|depth|imu|left|right|IMX|Stereo" >&2 || true
  return 1
}

bridge_topic() {
  local gz_topic="$1"
  local ros_topic="$2"
  local ros_type="$3"
  local gz_type="$4"

  wait_for_topic "${gz_topic}"
  echo "Bridging ${gz_topic} -> ${ros_topic}"
  ros2 run ros_gz_bridge parameter_bridge \
    "${gz_topic}@${ros_type}[${gz_type}" \
    --ros-args -r "${gz_topic}:=${ros_topic}" &
  pids+=("$!")
}

pids=()
cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

IFS=',' read -r -a streams <<<"${GZ_BRIDGE_STREAMS}"
for stream in "${streams[@]}"; do
  stream="${stream//[[:space:]]/}"
  case "${stream}" in
    left)
      bridge_topic "$(camera_topic "${GZ_LEFT_CAMERA_SENSOR}")" "${ROS_LEFT_IMAGE_TOPIC}" "sensor_msgs/msg/Image" "gz.msgs.Image"
      ;;
    right)
      bridge_topic "$(camera_topic "${GZ_RIGHT_CAMERA_SENSOR}")" "${ROS_RIGHT_IMAGE_TOPIC}" "sensor_msgs/msg/Image" "gz.msgs.Image"
      ;;
    rgb)
      bridge_topic "$(camera_topic "${GZ_RGB_CAMERA_SENSOR}")" "${ROS_RGB_IMAGE_TOPIC}" "sensor_msgs/msg/Image" "gz.msgs.Image"
      ;;
    imu)
      bridge_topic "$(imu_topic)" "${ROS_IMU_TOPIC}" "sensor_msgs/msg/Imu" "gz.msgs.IMU"
      ;;
    "")
      ;;
    *)
      echo "Unsupported GZ_BRIDGE_STREAMS entry: ${stream}" >&2
      exit 1
      ;;
  esac
done

if (( ${#pids[@]} == 0 )); then
  echo "No Gazebo bridge streams requested" >&2
  exit 1
fi

wait -n "${pids[@]}"
