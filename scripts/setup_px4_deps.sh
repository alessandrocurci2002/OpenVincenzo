#!/usr/bin/env bash
set -euo pipefail

PX4_DIR="${PX4_DIR:-/root/PX4-Autopilot}"

if [[ ! -f "${PX4_DIR}/Tools/setup/ubuntu.sh" ]]; then
  echo "PX4 setup script not found at ${PX4_DIR}/Tools/setup/ubuntu.sh" >&2
  echo "Run setup_px4_repo first, or initialize the PX4-Autopilot submodule on the host." >&2
  exit 1
fi

cd "${PX4_DIR}"
DEBIAN_FRONTEND=noninteractive bash ./Tools/setup/ubuntu.sh --no-nuttx
echo "PX4 Ubuntu dependencies installed"
