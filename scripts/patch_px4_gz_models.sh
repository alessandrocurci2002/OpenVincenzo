#!/usr/bin/env bash
set -euo pipefail

PX4_DIR="${PX4_DIR:-/root/PX4-Autopilot}"

if [[ ! -d "${PX4_DIR}" && -d "PX4-Autopilot" ]]; then
  PX4_DIR="PX4-Autopilot"
fi

gz_dir="${PX4_DIR}/Tools/simulation/gz"
baylands_sdf="${gz_dir}/worlds/baylands.sdf"
x500_sdf="${gz_dir}/models/x500/model.sdf"

if [[ ! -d "${gz_dir}" ]]; then
  echo "PX4 Gazebo models not found at ${gz_dir}" >&2
  exit 0
fi

if [[ -f "${baylands_sdf}" ]] && grep -q "<relative_to>park</relative_to>" "${baylands_sdf}"; then
  perl -0pi -e 's|(\s*)<pose>0 0 -2 0 0 0\s*<relative_to>park</relative_to>\s*</pose>|$1<pose relative_to="park">0 0 -2 0 0 0</pose>|s' "${baylands_sdf}"
  echo "Patched baylands.sdf pose relative_to syntax"
fi

if [[ -f "${x500_sdf}" ]] && grep -q "MotorFailurePlugin" "${x500_sdf}"; then
  perl -0pi -e 's|\n\s*<plugin\s+filename=["\x27]MotorFailurePlugin["\x27]\s+name=["\x27]gz::sim::systems::MotorFailureSystem["\x27]>\s*</plugin>||g' "${x500_sdf}"
  echo "Removed unsupported MotorFailurePlugin from x500 model"
fi
