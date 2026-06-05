# ============================================================
# Dockerfile  -  ROS 2 Humble + tmux
#                + GStreamer
#                + Gazebo Harmonic
#                + Micro-XRCE-DDS-Agent v2.4.3
#                + PX4-Autopilot v1.16.2 SITL
#                + Ceres Solver
#                + CLion remote debug (SSH)
# ============================================================
FROM ros:humble-ros-base-jammy AS runtime

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble

# ── Dipendenze base ───────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-rviz2 \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-vcstool \
        ca-certificates \
        tmux \
        git \
        wget \
        curl \
        gnupg \
        lsb-release \
        cmake \
        build-essential \
        gcc \
        g++ \
        gdb \
        clang \
        rsync \
        tar \
        usbutils \
        nano \
        ssh \
        openssh-server \
        python3-pip \
        python3-dev \
        python3-matplotlib \
        python3-numpy \
        python3-psutil \
        python3-tk \
        libeigen3-dev \
    && rm -rf /var/lib/apt/lists/*

# ── GStreamer ─────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer-plugins-bad1.0-dev \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
    && rm -rf /var/lib/apt/lists/*

# ── Gazebo Harmonic: repo OSRF + install ─────────────────────
RUN curl https://packages.osrfoundation.org/gazebo.gpg \
        --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends gz-harmonic ros-${ROS_DISTRO}-ros-gz-bridge && \
    rm -rf /var/lib/apt/lists/*

# ── Ceres Solver ─────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgoogle-glog-dev \
        libgflags-dev \
        libopenblas-dev \
        libsuitesparse-dev \
        libceres-dev \
    && rm -rf /var/lib/apt/lists/*

# Source ROS 2 per ogni sessione interattiva
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc

WORKDIR /root

# ── Micro-XRCE-DDS-Agent v2.4.3 ──────────────────────────────
RUN git clone -b v2.4.3 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git && \
    cd Micro-XRCE-DDS-Agent && \
    mkdir build && cd build && \
    cmake .. && \
    make && \
    make install && \
    ldconfig /usr/local/lib/ && \
    echo "Micro-XRCE-DDS-Agent Installed"

RUN git config --global --add safe.directory '*'

# ── OpenVINS: dipendenze (da Dockerfile_ros2_22_04) ──────────
# Eigen3, nano, Ceres solver e librerie Python per ov_eval
RUN apt-get update && \
    apt-get install -y \
        libeigen3-dev \
        nano \
        libgoogle-glog-dev \
        libgflags-dev \
        libatlas-base-dev \
        libsuitesparse-dev \
        libceres-dev \
        python3-dev \
        python3-matplotlib \
        python3-numpy \
        python3-psutil \
        python3-tk \
    && rm -rf /var/lib/apt/lists/*



# ── OpenVINS: workspace ROS 2 (sorgenti montati a runtime) ───

RUN apt-get update && \
    apt-get install -y \
        libatlas-base-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/colcon_ws/src

# ── Shortcut bridge wrappers ─────────────────────────────────
RUN printf '#!/bin/bash\nGZ_BRIDGE_STREAMS=rgb exec run_gz_stereo_bridge "$@"\n' \
    > /usr/local/bin/run_image_bridge && \
    chmod +x /usr/local/bin/run_image_bridge

RUN printf '#!/bin/bash\nGZ_BRIDGE_STREAMS=left exec run_gz_stereo_bridge "$@"\n' \
    > /usr/local/bin/run_image_bridge_left && \
    chmod +x /usr/local/bin/run_image_bridge_left

RUN printf '#!/bin/bash\nGZ_BRIDGE_STREAMS=right exec run_gz_stereo_bridge "$@"\n' \
    > /usr/local/bin/run_image_bridge_right && \
    chmod +x /usr/local/bin/run_image_bridge_right

RUN printf '#!/bin/bash\necho "Pointcloud bridge is intentionally not enabled for OpenVINS stereo. Use run_gz_stereo_bridge for left/right/IMU topics." >&2\nexit 1\n' \
    > /usr/local/bin/run_pointcloud_bridge && \
    chmod +x /usr/local/bin/run_pointcloud_bridge

RUN printf '#!/bin/bash\nGZ_BRIDGE_STREAMS=imu exec run_gz_stereo_bridge "$@"\n' \
    > /usr/local/bin/run_imu_bridge && \
    chmod +x /usr/local/bin/run_imu_bridge

# ── CLion remote debug via SSH ───────────────────────────────
# https://blog.jetbrains.com/clion/2020/01/using-docker-with-clion/
RUN ( \
    echo 'LogLevel DEBUG2'; \
    echo 'PermitRootLogin yes'; \
    echo 'PasswordAuthentication yes'; \
    echo 'Subsystem sftp /usr/lib/openssh/sftp-server'; \
  ) > /etc/ssh/sshd_config_test_clion \
  && mkdir /run/sshd
RUN useradd -m user && yes password | passwd user && usermod -s /bin/bash user

# CMD ["bash", "-c", "\
# DEBIAN_FRONTEND=noninteractive /usr/sbin/sshd && \
# cd /root/PX4-Autopilot && \
# DEBIAN_FRONTEND=noninteractive bash ./Tools/setup/ubuntu.sh --no-nuttx && \
# echo 'PX4-Autopilot Installed' && \
# source /opt/ros/humble/setup.bash && \
# apt-get update && \
# cd /root/colcon_ws && \
# rosdep install --from-paths src --ignore-src -r -y && \
# MAKEFLAGS='-j2' colcon build --symlink-install \
#     --executor sequential \
#     --packages-select ov_core ov_init ov_msckf ov_eval && \
# rm -rf /var/lib/apt/lists/* && \
# tmux new-session -A -s main"]

COPY entrypoint.sh /entrypoint.sh
COPY scripts/smoke_no_oak.sh /usr/local/bin/smoke_no_oak
COPY scripts/smoke_oak.sh /usr/local/bin/smoke_oak
COPY scripts/run_oak_stereo.sh /usr/local/bin/run_oak_stereo
COPY scripts/patch_px4_gz_models.sh /usr/local/bin/patch_px4_gz_models
COPY scripts/run_gz_stereo_bridge.sh /usr/local/bin/run_gz_stereo_bridge
COPY scripts/run_1.sh /usr/local/bin/run_1
COPY scripts/run_px4_baylands_H1.sh /usr/local/bin/run_px4_baylands_H1
COPY scripts/setup_px4_repo.sh /usr/local/bin/setup_px4_repo
COPY scripts/setup_px4_deps.sh /usr/local/bin/setup_px4_deps
RUN sed -i 's/\r$//' /entrypoint.sh \
    /usr/local/bin/smoke_no_oak \
    /usr/local/bin/smoke_oak \
    /usr/local/bin/run_oak_stereo \
    /usr/local/bin/patch_px4_gz_models \
    /usr/local/bin/run_gz_stereo_bridge \
    /usr/local/bin/run_1 \
    /usr/local/bin/run_px4_baylands_H1 \
    /usr/local/bin/setup_px4_repo \
    /usr/local/bin/setup_px4_deps && \
    chmod +x /entrypoint.sh \
    /usr/local/bin/smoke_no_oak \
    /usr/local/bin/smoke_oak \
    /usr/local/bin/run_oak_stereo \
    /usr/local/bin/patch_px4_gz_models \
    /usr/local/bin/run_gz_stereo_bridge \
    /usr/local/bin/run_1 \
    /usr/local/bin/run_px4_baylands_H1 \
    /usr/local/bin/setup_px4_repo \
    /usr/local/bin/setup_px4_deps

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tmux", "new-session", "-A", "-s", "main"]

FROM runtime AS production

# Optional OAK-D Pro profile. The default production target above stays on the
# stable ROS apt repository; this target enables the ROS testing repository only
# where Luxonis requires it for Humble/Jazzy v3 binaries.
FROM runtime AS oak
ARG ENABLE_ROS_TESTING_REPO=1
RUN if [[ "${ENABLE_ROS_TESTING_REPO}" == "1" ]]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends ros2-testing-apt-source; \
    fi && \
    apt-get update && \
    apt-get install -y --no-install-recommends ros-${ROS_DISTRO}-depthai-ros-v3 && \
    rm -rf /var/lib/apt/lists/*
ENV OPENVINCENZO_OAK_PROFILE=1
