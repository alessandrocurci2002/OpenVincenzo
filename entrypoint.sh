#!/usr/bin/env bash
set -e

# export DEBIAN_FRONTEND=noninteractive

# /usr/sbin/sshd

source /opt/ros/humble/setup.bash


echo "+++ Updating"
apt-get update
echo "+++ Finished Updating"


echo "+++ Sourcing and Building depthai-ros"
source /opt/ros/$ROS_DISTRO/setup.bash
cd /root/depthai-ws/src
git clone https://github.com/luxonis/depthai-core.git
cd depthai-core && git submodule update --init --recursive && cd ..
colcon build --symlink-install
source /root/depthai-ws/install/setup.bash
echo "+++ depthai-ros Build Completed "


cd /root/colcon_ws
echo "+++ Installing dependencies for OpenVINS..."
rosdep install --from-paths src --ignore-src -r -y
echo "+++ Finished installing dependencies for OpenVINS"


echo "+++ Building OpenVINS"
MAKEFLAGS="-j2" colcon build --symlink-install \
    --executor sequential \
    --packages-select ov_core ov_init ov_msckf ov_eval

rm -rf /var/lib/apt/lists/*
echo "+++ OpenVINS Build Completed "



exec "$@"