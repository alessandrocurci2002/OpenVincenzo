#!/usr/bin/env bash
set -e

# export DEBIAN_FRONTEND=noninteractive

# /usr/sbin/sshd

source /opt/ros/humble/setup.bash


echo "+++ Updating"
apt-get update
apt install ros-$ROS_DISTRO-rviz2
echo "+++ Finished Updating"


echo "+++ Sourcing and Building depthai"
source /opt/ros/$ROS_DISTRO/setup.bash

cd /root/depthai-ws/src/depthai-core
# git checkout v3_humble
# git submodule update --init --recursive
cd ..
cd /root/depthai-ws/src/depthai-ros
# git checkout v3_humble
# git submodule update --init --recursive 
cd ..

cd /root/depthai-ws
rosdep install --from-paths src --ignore-src -r -y
MAKEFLAGS="-j1 -l1" colcon build --symlink-install
source /root/depthai-ws/install/setup.bash

echo "+++ depthai Build Completed "


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