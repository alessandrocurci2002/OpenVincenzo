#!/usr/bin/env bash
set -euo pipefail

PX4_DIR="${PX4_DIR:-/root/PX4-Autopilot}"
ROS_DISTRO="${ROS_DISTRO:-humble}"
PX4_GZ_WORLD="${PX4_GZ_WORLD:-baylands}"
PX4_GZ_MODEL="${PX4_GZ_MODEL:-gz_x500_depth}"

source_setup() {
  set +u
  source "$1"
  set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"

if [[ ! -f "${PX4_DIR}/Makefile" ]]; then
  echo "PX4 Makefile not found in ${PX4_DIR}" >&2
  echo "Run setup_px4_repo, or initialize the PX4-Autopilot submodule on the host." >&2
  exit 1
fi

plugin_dir="${PX4_DIR}/build/px4_sitl_default/src/modules/simulation/gz_plugins"
export GZ_SIM_SYSTEM_PLUGIN_PATH="${plugin_dir}${GZ_SIM_SYSTEM_PLUGIN_PATH:+:${GZ_SIM_SYSTEM_PLUGIN_PATH}}"

cd "${PX4_DIR}"
HEADLESS=1 PX4_GZ_WORLD="${PX4_GZ_WORLD}" make px4_sitl "${PX4_GZ_MODEL}"
