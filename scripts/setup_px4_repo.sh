#!/usr/bin/env bash
set -euo pipefail

PX4_DIR="${PX4_DIR:-/root/PX4-Autopilot}"
PX4_REPO="${PX4_REPO:-https://github.com/FedericoDD/PX4-Autopilot.git}"
PX4_BRANCH="${PX4_BRANCH:-v1.16.2-stereo}"

mkdir -p "${PX4_DIR}"

if [[ -d "${PX4_DIR}/.git" ]]; then
  cd "${PX4_DIR}"
  git fetch --recurse-submodules origin "${PX4_BRANCH}"
  git checkout "${PX4_BRANCH}"
  git submodule sync --recursive
  git submodule update --init --recursive
  echo "PX4 repository updated in ${PX4_DIR}"
  exit 0
fi

if find "${PX4_DIR}" -mindepth 1 -maxdepth 1 | grep -q .; then
  echo "${PX4_DIR} is not empty and is not a Git repository." >&2
  echo "Initialize PX4 on the host with: git submodule update --init --recursive PX4-Autopilot" >&2
  exit 1
fi

git clone --recursive --branch "${PX4_BRANCH}" "${PX4_REPO}" "${PX4_DIR}"
cd "${PX4_DIR}"
git submodule update --init --recursive
echo "PX4 repository cloned in ${PX4_DIR}"
