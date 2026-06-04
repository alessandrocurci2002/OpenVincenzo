#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
OAK_LAUNCH_FILE="${OAK_LAUNCH_FILE:-rgbd_pcl.launch.py}"
OAK_BOOT_SECONDS="${OAK_BOOT_SECONDS:-10}"
OAK_TOPIC_PATTERN="${OAK_TOPIC_PATTERN:-/oak|/camera|/rgb|/stereo|/depth|/imu}"

source_setup() {
  set +u
  source "$1"
  set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f /root/colcon_ws/install/setup.bash ]]; then
  source_setup /root/colcon_ws/install/setup.bash
fi

ros2 pkg prefix depthai_ros_driver_v3 >/dev/null 2>&1 || {
  echo "Missing ROS package: depthai_ros_driver_v3. Build with: docker build --target oak ..." >&2
  exit 1
}

command -v lsusb >/dev/null 2>&1 || {
  echo "Missing command: lsusb" >&2
  exit 1
}

if ! lsusb | grep -qi '03e7'; then
  echo "No Luxonis/Movidius USB device found (vendor id 03e7)." >&2
  echo "Check the OAK-D Pro cable, external power/powered hub, host udev rule, and Docker USB mapping." >&2
  exit 2
fi

ros2 launch depthai_ros_driver_v3 "${OAK_LAUNCH_FILE}" --show-args >/tmp/oak_launch_args.txt

log_file=/tmp/oak_driver.log
topics_file=/tmp/oak_topics.txt
launch_pid=""

cleanup() {
  if [[ -n "${launch_pid}" ]] && kill -0 "${launch_pid}" >/dev/null 2>&1; then
    kill "${launch_pid}" >/dev/null 2>&1 || true
    wait "${launch_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ros2 launch depthai_ros_driver_v3 "${OAK_LAUNCH_FILE}" "$@" >"${log_file}" 2>&1 &
launch_pid="$!"

sleep "${OAK_BOOT_SECONDS}"

if ! kill -0 "${launch_pid}" >/dev/null 2>&1; then
  echo "OAK driver exited before topics were available. Log follows:" >&2
  tail -n 80 "${log_file}" >&2 || true
  exit 1
fi

ros2 topic list >"${topics_file}"

if ! grep -E "${OAK_TOPIC_PATTERN}" "${topics_file}" >/dev/null 2>&1; then
  echo "OAK driver is running but expected camera topics were not found. Topics follow:" >&2
  cat "${topics_file}" >&2
  echo "Driver log follows:" >&2
  tail -n 80 "${log_file}" >&2 || true
  exit 1
fi

echo "smoke_oak: OK"
cat "${topics_file}"
