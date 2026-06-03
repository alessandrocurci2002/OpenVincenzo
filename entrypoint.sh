#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

/usr/sbin/sshd

cd /root/PX4-Autopilot
bash ./Tools/setup/ubuntu.sh --no-nuttx
echo "PX4-Autopilot Installed"

source /opt/ros/humble/setup.bash

apt-get update

cd /root/colcon_ws
rosdep install --from-paths src --ignore-src -r -y

MAKEFLAGS="-j2" colcon build --symlink-install \
    --executor sequential \
    --packages-select ov_core ov_init ov_msckf ov_eval

rm -rf /var/lib/apt/lists/*

exec "$@"