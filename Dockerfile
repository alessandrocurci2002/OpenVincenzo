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
    apt-get install -y --no-install-recommends gz-harmonic && \
    apt-get update && \
    apt-get install -y --no-install-recommends ros2-testing-apt-source && \
    apt-get update && \
    apt-get install -y --no-install-recommends ros-${ROS_DISTRO}-diagnostic-updater && \
    apt-get update && \
    apt-get install -y --no-install-recommends ros-${ROS_DISTRO}-diagnostic-msgs && \
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



# ── OpenVINS: workspace ROS 2 + clone ────────────────────────

RUN apt-get update && \
    apt-get install -y \
        libatlas-base-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/colcon_ws/src

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


COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tmux", "new-session", "-A", "-s", "main"]