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

cd /root/depthai-ws/src
if ! git -C depthai-core rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # depthai-core is a git submodule on the host: its .git file points to
    # ../../../.git/modules/depthai-core, which lives outside depthai-ws and
    # is not mounted into the container, so we clone it fresh here instead.
    rm -rf depthai-core
    git clone --branch v3_humble https://github.com/luxonis/depthai-core.git depthai-core
    git -C depthai-core checkout 98934d38cbf71791b6f1f393b91d86724f5aabc4
fi
cd depthai-core
git submodule update --init --recursive
cd ..
cd /root/depthai-ws/src
if ! git -C depthai-ros rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # same issue as depthai-core: the host .git file points to
    # ../../../.git/modules/OAK-ROS-depthai, not mounted into the container
    rm -rf depthai-ros
    git clone --branch v3_humble https://github.com/alessandrocurci2002/depthai-ros.git depthai-ros
    git -C depthai-ros checkout 7aec66fdf53d5564b94bd801123b8ef43f0e30a7
fi
cd depthai-ros
# depthai-ros's own .gitmodules has a malformed "path" for the kalibr
# submodule (it records "depthai-ws/src/depthai-ros/calibration" instead of
# "calibration/kalibr", the actual gitlink path), so "git submodule update
# --init" fails outright with "No url found for submodule path
# 'calibration/kalibr'" even without --recursive. depthai-ros has no other
# submodule, so skip the git-submodule machinery entirely and clone kalibr
# directly instead.
if ! git -C calibration/kalibr rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    rm -rf calibration/kalibr
    git clone --branch master https://github.com/ethz-asl/kalibr.git calibration/kalibr
    git -C calibration/kalibr checkout 1f60227442d25e36365ef5f72cd80b9666d73467
fi
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