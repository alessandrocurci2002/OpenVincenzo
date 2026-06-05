#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"

source_setup() {
  set +u
  source "$1"
  set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f /root/colcon_ws/install/setup.bash ]]; then
  source_setup /root/colcon_ws/install/setup.bash
fi

check_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "Missing command: ${cmd}" >&2
    exit 1
  }
}

check_pkg() {
  local pkg="$1"
  ros2 pkg prefix "${pkg}" >/dev/null 2>&1 || {
    echo "Missing ROS package: ${pkg}" >&2
    exit 1
  }
}

optional_pkg() {
  local pkg="$1"
  if ros2 pkg prefix "${pkg}" >/dev/null 2>&1; then
    echo "OK optional ROS package: ${pkg}"
  else
    echo "SKIP optional ROS package: ${pkg}"
  fi
}

check_px4_gz_patch() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf -- '${tmp}'" EXIT

  mkdir -p \
    "${tmp}/Tools/simulation/gz/worlds" \
    "${tmp}/Tools/simulation/gz/models/x500"

  cat > "${tmp}/Tools/simulation/gz/worlds/baylands.sdf" <<'EOF'
<sdf version="1.9">
  <world name="baylands">
    <pose>0 0 -2 0 0 0
      <relative_to>park</relative_to>
    </pose>
  </world>
</sdf>
EOF

  cat > "${tmp}/Tools/simulation/gz/models/x500/model.sdf" <<'EOF'
<sdf version="1.9">
  <model name="x500">
    <plugin filename="MotorFailurePlugin" name="gz::sim::systems::MotorFailureSystem">
    </plugin>
  </model>
</sdf>
EOF

  PX4_DIR="${tmp}" patch_px4_gz_models
  PX4_DIR="${tmp}" patch_px4_gz_models --check
}

check_cmd ros2
check_cmd rviz2
check_cmd gz
check_cmd MicroXRCEAgent
check_cmd patch_px4_gz_models
check_cmd run_gz_stereo_bridge
check_cmd run_1

check_pkg rviz2
check_pkg ros_gz_bridge
check_pkg sensor_msgs

optional_pkg ov_core
optional_pkg ov_init
optional_pkg ov_msckf
optional_pkg ov_eval

check_px4_gz_patch

echo "smoke_no_oak: OK"
