#!/usr/bin/env bash
set -e

# export DEBIAN_FRONTEND=noninteractive

# /usr/sbin/sshd

source /opt/ros/humble/setup.bash

# Isolate this system's ROS2 graph from other ROS2 traffic on the LAN
# (default ROS_DOMAIN_ID=0 was picking up ghost /oak nodes from elsewhere
# on the network, causing ros2 launch to hang waiting on the wrong
# load_node service response).
export ROS_DOMAIN_ID=42

# `make` is run from /root: link the Makefile from the read-only repo mount
# (see dockerRun.sh for why it is not a single-file mount). Skipped when
# /root/Makefile already exists, e.g. in containers created with the old
# single-file mount, where replacing a mount point would fail.
if [ ! -e /root/Makefile ] && [ ! -L /root/Makefile ]; then
    ln -s /root/OpenVincenzo/Makefile /root/Makefile
fi


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


# px4_msgs: le interfacce ROS 2 generate dai .msg/.srv del fork PX4-Autopilot
# (submodule px4-ws/PX4-Autopilot, branch PX4-Autopilot/v1.17.0). Si compilano
# SOLO i messaggi, non il firmware. Il submodule sta fuori da px4-ws/src e la
# build usa --base-paths src: cosi' colcon non vede i package.xml/CMakeLists del
# fork (px4, msg, copie di px4_msgs_old e translation_node) e non prova a buildarli.
# Il submodule e' uno sparse checkout (solo msg/, srv/ e copy_to_ros_ws.sh) e si
# inizializza sull'host con lo script dedicato, non con git submodule update:
#   ./scripts/init_px4_submodule.sh
PX4_WS=/root/px4-ws
PX4_SRC=$PX4_WS/PX4-Autopilot
echo "+++ Building px4_msgs from PX4-Autopilot fork"
if [ ! -x "$PX4_SRC/Tools/copy_to_ros_ws.sh" ]; then
    echo "!!! WARNING: $PX4_SRC non inizializzato, salto la build di px4_msgs."
    echo "!!! Sull'host: ./scripts/init_px4_submodule.sh"
else
    mkdir -p $PX4_WS/src
    # copy_to_ros_ws.sh clonerebbe px4_msgs dal branch di default (main): lo
    # clono io da release/1.17 (solo CMakeLists/package.xml, i .msg vengono
    # sostituiti da quelli del fork).
    if [ ! -d $PX4_WS/src/px4_msgs ]; then
        git clone --depth 1 --branch release/1.17 https://github.com/PX4/px4_msgs.git $PX4_WS/src/px4_msgs
        rm -f $PX4_WS/src/px4_msgs/msg/*.msg $PX4_WS/src/px4_msgs/msg/versioned/*.msg $PX4_WS/src/px4_msgs/srv/*.srv
    fi
    # copia px4_msgs (.msg/.srv del fork), px4_msgs_old e translation_node in px4-ws/src
    $PX4_SRC/Tools/copy_to_ros_ws.sh $PX4_WS
    # rosidl accetta solo nomi CamelCase: il fork ha light_board.msg (topic uORB
    # custom, non usato dal bridge DDS), lo escludo dal pacchetto.
    find $PX4_WS/src/px4_msgs/msg $PX4_WS/src/px4_msgs/srv -type f \( -name '*.msg' -o -name '*.srv' \) \
        ! -regex '.*/[A-Z][A-Za-z0-9]*\.\(msg\|srv\)' -print -delete | sed 's/^/+++ px4_msgs: escluso (non CamelCase) /'

    cd $PX4_WS
    rosdep install --from-paths src --ignore-src -r -y
    # --base-paths src: senza, colcon scansiona tutto px4-ws (base-path di default
    # = ".") e trova anche PX4-Autopilot/msg/CMakeLists.txt (lo prende per un
    # pacchetto "msg" e fallisce) e le copie di px4_msgs_old/translation_node.
    MAKEFLAGS="-j2" colcon build --symlink-install --base-paths src
    source $PX4_WS/install/setup.bash
    echo "+++ px4_msgs Build Completed "
fi


cd /root/colcon_ws
echo "+++ Installing dependencies for OpenVINS..."
rosdep install --from-paths src --ignore-src -r -y
echo "+++ Finished installing dependencies for OpenVINS"



echo "+++ Building OpenVINS"
MAKEFLAGS="-j2" colcon build --symlink-install \
    --executor sequential \
    --packages-select ov_core ov_init ov_msckf ov_eval

echo "+++ OpenVINS Build Completed "


echo "+++ Building px4_vio_bridge"
MAKEFLAGS="-j2" colcon build --symlink-install \
    --executor sequential \
    --packages-select px4_vio_bridge

echo "+++ px4_vio_bridge Build Completed "


echo "+++ Building oak_stream_server"
MAKEFLAGS="-j2" colcon build --symlink-install \
    --executor sequential \
    --packages-select oak_stream_server

echo "+++ oak_stream_server Build Completed "

# Unlike depthai-ws and px4-ws above, colcon_ws was never sourced for the
# entrypoint's own shell (only rebuilt): without this, ov_msckf,
# px4_vio_bridge and oak_stream_server are invisible to `ros2 run`/`launch`
# in every shell spawned from this entrypoint (tmux panes, `docker exec`
# inheriting this env via `exec "$@"` below) until sourced by hand.
source /root/colcon_ws/install/setup.bash

rm -rf /var/lib/apt/lists/*

exec "$@"