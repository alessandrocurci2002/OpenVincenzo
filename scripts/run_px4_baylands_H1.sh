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

prepend_existing_path() {
  local var_name="$1"
  local path="$2"
  local current="${!var_name:-}"

  [[ -d "${path}" ]] || return 0

  case ":${current}:" in
    *":${path}:"*) return 0 ;;
  esac

  if [[ -n "${current}" ]]; then
    printf -v "${var_name}" "%s:%s" "${path}" "${current}"
  else
    printf -v "${var_name}" "%s" "${path}"
  fi

  export "${var_name}"
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"

if [[ ! -f "${PX4_DIR}/Makefile" ]]; then
  echo "PX4 Makefile not found in ${PX4_DIR}" >&2
  echo "Run setup_px4_repo, or initialize the PX4-Autopilot submodule on the host." >&2
  exit 1
fi

patch_px4_gz_models --check || {
  echo "PX4 Gazebo model patches are missing. Run on the host: make patch-px4-gz-host" >&2
  exit 1
}

px4_build_dir="${PX4_DIR}/build/px4_sitl_default"
px4_gz_env="${px4_build_dir}/rootfs/gz_env.sh"

if [[ -f "${px4_gz_env}" ]]; then
  source_setup "${px4_gz_env}"
fi

prepend_existing_path GZ_SIM_RESOURCE_PATH "${PX4_DIR}/Tools/simulation/gz"
prepend_existing_path GZ_SIM_RESOURCE_PATH "${PX4_DIR}/Tools/simulation/gz/worlds"
prepend_existing_path GZ_SIM_RESOURCE_PATH "${PX4_DIR}/Tools/simulation/gz/models"

prepend_existing_path GZ_SIM_SYSTEM_PLUGIN_PATH "${px4_build_dir}/src/modules/simulation/gz_plugins"
prepend_existing_path GZ_SIM_SYSTEM_PLUGIN_PATH "${px4_build_dir}/build_gz"

if [[ -d "${px4_build_dir}" ]]; then
  while IFS= read -r -d '' plugin_dir; do
    prepend_existing_path GZ_SIM_SYSTEM_PLUGIN_PATH "${plugin_dir}"
  done < <(find "${px4_build_dir}" -type f \( -name "*.so" -o -name "MotorFailurePlugin" \) -printf "%h\0" | sort -zu)
fi

if grep -R "MotorFailurePlugin" -n "${PX4_DIR}/Tools/simulation/gz" >/dev/null 2>&1 &&
   ! find "${px4_build_dir}" -type f \( -name "*MotorFailure*" -o -name "MotorFailurePlugin" \) -print -quit 2>/dev/null | grep -q .; then
  echo "Warning: PX4 SDF files reference MotorFailurePlugin, but no matching library was found under ${px4_build_dir}." >&2
  echo "If MotorFailurePlugin is required by this fork, rebuild PX4 on this architecture or fix the SDF plugin filename/path." >&2
fi

cd "${PX4_DIR}"
HEADLESS=1 PX4_GZ_WORLD="${PX4_GZ_WORLD}" make px4_sitl "${PX4_GZ_MODEL}"
