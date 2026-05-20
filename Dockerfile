# ============================================================
# Dockerfile  –  ROS 2 Humble + tmux
#                + GStreamer
#                + Gazebo Harmonic
#                + Micro-XRCE-DDS-Agent v2.4.3
#                + PX4-Autopilot v1.16.2 SITL
#                + Ceres Solver
#                + CLion remote debug (SSH)
# ============================================================
FROM osrf/ros:humble-desktop-full

SHELL ["/bin/bash", "-c"]

# ── Dipendenze base ───────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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
        nano \
        ssh \
        openssh-server\
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
    apt-get install -y gz-harmonic ros-humble-ros-gzharmonic && \
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
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc

WORKDIR /root

# RUN git clone --recursive -b v1.16.2-stereo https://github.com/FedericoDD/PX4-Autopilot.git && \
#     echo "PX4 Downloaded"


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

# ── Shortcut: install_px4 ─────────────────────────────────────


# ── Shortcut: run_px4_baylands_H1 ────────────────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\ncd /root/PX4-Autopilot\nHEADLESS=1 PX4_GZ_WORLD=baylands make px4_sitl gz_x500_depth\n' \
    > /usr/local/bin/run_px4_baylands_H1 && \
    chmod +x /usr/local/bin/run_px4_baylands_H1

# ── Shortcut: run_image_bridge ───────────────────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge /world/baylands/model/x500_depth_0/link/camera_link/sensor/IMX214/image@sensor_msgs/msg/Image[gz.msgs.Image\n' \
    > /usr/local/bin/run_image_bridge && \
    chmod +x /usr/local/bin/run_image_bridge

# ── Shortcut: run_image_bridge_left ───────────────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge /world/baylands/model/x500_depth_0/link/camera_link/sensor/left_camera/image@sensor_msgs/msg/Image[gz.msgs.Image\n' \
    > /usr/local/bin/run_image_bridge_left && \
    chmod +x /usr/local/bin/run_image_bridge_left

# ── Shortcut: run_image_bridge_right ──────────────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge /world/baylands/model/x500_depth_0/link/camera_link/sensor/right_camera/image@sensor_msgs/msg/Image[gz.msgs.Image\n' \
    > /usr/local/bin/run_image_bridge_right && \
    chmod +x /usr/local/bin/run_image_bridge_right

# ── Shortcut: run_pointcloud_bridge ──────────────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge \\\n  /depth_camera/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked \\\n  /depth_camera@sensor_msgs/msg/Image[gz.msgs.Image \\\n  /camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo\n' \
    > /usr/local/bin/run_pointcloud_bridge && \
    chmod +x /usr/local/bin/run_pointcloud_bridge

# ── Shortcut: run_1 (tutti i bridge + PX4) ───────────────────
RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nrun_image_bridge &\nrun_pointcloud_bridge &\nrun_px4_baylands_H1\n' \
    > /usr/local/bin/run_1 && \
    chmod +x /usr/local/bin/run_1

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

CMD ["bash", "-c", "DEBIAN_FRONTEND=noninteractive /usr/sbin/sshd && cd /root/PX4-Autopilot && DEBIAN_FRONTEND=noninteractive bash ./Tools/setup/ubuntu.sh --no-nuttx && echo 'PX4-Autopilot Installed' && tmux new-session -A -s main"]