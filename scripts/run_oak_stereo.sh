#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
OAK_LAUNCH_FILE="${OAK_LAUNCH_FILE:-rgbd_pcl.launch.py}"

source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f /root/colcon_ws/install/setup.bash ]]; then
  source /root/colcon_ws/install/setup.bash
fi

ros2 pkg prefix depthai_ros_driver_v3 >/dev/null 2>&1 || {
  echo "Missing ROS package: depthai_ros_driver_v3. Build with: docker build --target oak ..." >&2
  exit 1
}

exec ros2 launch depthai_ros_driver_v3 "${OAK_LAUNCH_FILE}" "$@"
