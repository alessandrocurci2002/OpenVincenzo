# ============================================================
# Dockerfile  –  ROS 2 Humble + tmux
#                + GStreamer
#                + Gazebo Harmonic
#                + Micro-XRCE-DDS-Agent v2.4.2 (uXRCE-DDS, PX4 <-> ROS 2, Fast-DDS di ROS)
#                + Ceres Solver
#                + CLion remote debug (SSH)
# ============================================================
FROM ros:humble

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

# ── Micro-XRCE-DDS-Agent v2.4.2 (uXRCE-DDS: PX4 <-> ROS 2) ───
# Installazione standalone da sorgente (opzione 1 della doc PX4):
# https://docs.px4.io/main/en/middleware/uxrce_dds#humble
# La doc fissa per Humble: Fast-DDS 2.6.x + agent 2.4.2, e precisa che la
# versione DDS e' decisa dalla distro ROS 2. Quindi l'agent va compilato contro
# la Fast-DDS/Fast-CDR di ROS Humble (/opt/ros/humble), NON contro una sua copia:
# con il default del superbuild avremmo due Fast-DDS nel container (2.12 in
# /usr/local + 2.6 in /opt/ros), con libfastcdr.so.1 di due versioni diverse.
# Il default e' comunque rotto: cerca il branch "2.12.x" di Fast-DDS, rimosso da
# GitHub ("invalid reference: 2.12.x"). Stessa ricetta del micro_ros_agent per
# Humble: tag v2.4.2 con UAGENT_USE_SYSTEM_FASTDDS/FASTCDR=ON (P2P e CED spenti
# come li' perche' non servono). Uso: MicroXRCEAgent udp4 -p 8888
# A runtime l'agent trova le librerie in /opt/ros/humble/lib: serve ROS 2
# sourced (lo e' nel .bashrc e nell'entrypoint).
# --no-upgrade: fastrtps/fastcdr sono gia' nell'immagine base; con
# ros2-testing-apt-source abilitato sopra, senza il flag apt potrebbe
# aggiornarli a una versione di testing.
RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-upgrade \
        ros-${ROS_DISTRO}-fastrtps \
        ros-${ROS_DISTRO}-fastcdr \
        ros-${ROS_DISTRO}-foonathan-memory-vendor \
        libasio-dev \
        libtinyxml2-dev \
    && rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 --branch v2.4.2 \
        https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /tmp/Micro-XRCE-DDS-Agent && \
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    cmake -S /tmp/Micro-XRCE-DDS-Agent -B /tmp/Micro-XRCE-DDS-Agent/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/ros/${ROS_DISTRO} \
        -DUAGENT_USE_SYSTEM_FASTDDS=ON \
        -DUAGENT_USE_SYSTEM_FASTCDR=ON \
        -DUAGENT_P2P_PROFILE=OFF \
        -DUAGENT_CED_PROFILE=OFF && \
    cmake --build /tmp/Micro-XRCE-DDS-Agent/build -j"$(nproc)" && \
    cmake --install /tmp/Micro-XRCE-DDS-Agent/build && \
    ldconfig /usr/local/lib/ && \
    rm -rf /tmp/Micro-XRCE-DDS-Agent

# Smoke test, con ROS 2 sourced: nessuna libreria mancante/simbolo non risolto e
# Fast-DDS/Fast-CDR risolte SOLO da /opt/ros/humble (nessuna seconda copia).
RUN source /opt/ros/${ROS_DISTRO}/setup.bash && \
    ldd -r /usr/local/bin/MicroXRCEAgent && \
    ! ldd -r /usr/local/bin/MicroXRCEAgent 2>&1 | grep -E "not found|undefined symbol" && \
    ldd /usr/local/bin/MicroXRCEAgent | grep -E "libfastrtps|libfastcdr" && \
    ! ldd /usr/local/bin/MicroXRCEAgent | grep -E "libfastrtps|libfastcdr" | grep -v "/opt/ros/${ROS_DISTRO}/"

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

# ── oak_stream_server: MJPEG viewer for /oak/left/image_rect ─
# python3-flask has no dependable rosdep key, so it's installed here
# directly instead of via package.xml + `rosdep install` (see the
# package's README). cv_bridge/OpenCV come from rosdep at container start,
# same as for OpenVINS.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-flask \
    && rm -rf /var/lib/apt/lists/*

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