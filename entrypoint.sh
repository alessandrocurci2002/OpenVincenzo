#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
ROS_DISTRO="${ROS_DISTRO:-humble}"

source_setup() {
    set +u
    source "$1"
    set -u
}

source_setup "/opt/ros/${ROS_DISTRO}/setup.bash"

if [[ "${START_SSHD:-1}" == "1" ]]; then
    mkdir -p /run/sshd
    /usr/sbin/sshd -f /etc/ssh/sshd_config_test_clion
fi

if [[ "${RUN_PX4_SETUP:-1}" == "1" ]]; then
    if [[ -f /root/PX4-Autopilot/Tools/setup/ubuntu.sh ]]; then
        cd /root/PX4-Autopilot
        bash ./Tools/setup/ubuntu.sh --no-nuttx
        echo "PX4-Autopilot setup complete"
    else
        echo "PX4 setup skipped: /root/PX4-Autopilot is not mounted"
    fi
fi

if [[ "${BUILD_OPENVINS:-1}" == "1" ]]; then
    if [[ -d /root/colcon_ws/src ]] && find /root/colcon_ws/src -name package.xml -print -quit | grep -q .; then
        apt-get update

        cd /root/colcon_ws
        rosdep install --from-paths src --ignore-src -r -y

        MAKEFLAGS="${MAKEFLAGS:-"-j2"}" colcon build --symlink-install \
            --executor sequential \
            --packages-select ov_core ov_init ov_msckf ov_eval

        rm -rf /var/lib/apt/lists/*
    else
        echo "OpenVINS build skipped: no ROS packages found under /root/colcon_ws/src"
    fi
fi

if [[ -f /root/colcon_ws/install/setup.bash ]]; then
    source_setup /root/colcon_ws/install/setup.bash
fi

exec "$@"
