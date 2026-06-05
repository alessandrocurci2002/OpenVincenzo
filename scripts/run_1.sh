#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"

source_setup() {
  set +u
  source "$1"
  set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"

bridge_pid=""
cleanup() {
  if [[ -n "${bridge_pid}" ]]; then
    kill "${bridge_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "${RUN_ROS_GZ_BRIDGES:-0}" == "1" ]]; then
  run_gz_stereo_bridge &
  bridge_pid="$!"
else
  echo "ROS-Gazebo stereo bridge skipped; set RUN_ROS_GZ_BRIDGES=1 to enable it."
fi

run_px4_baylands_H1
