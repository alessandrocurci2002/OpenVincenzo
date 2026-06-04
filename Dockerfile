# ============================================================
# Dockerfile  –  ROS 2 Humble + tmux
#                + GStreamer
#                + Gazebo Harmonic
#                + OpenVINS (ROS 2 Humble / Ubuntu 22.04)
#
# Sections PX4 e Micro-XRCE-DDS-Agent were commented
# in order to speed up the building process for the OpenVinsDataSet
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
        python3-pip \
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

# Source ROS 2 per ogni sessione interattiva
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc

# Dependencies for MacOS
RUN apt-get update && apt-get install -y \
    xvfb \
    mesa-utils \
    libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# ── [COMMENTED] Micro-XRCE-DDS-Agent v2.4.3 ─────────────────
# Commentato per velocizzare il build durante lo sviluppo con OpenVINS.
# Decommentare quando si riattiva l'integrazione con PX4.
#
# RUN git clone -b v2.4.3 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git && \
#     cd Micro-XRCE-DDS-Agent && \
#     mkdir build && cd build && \
#     cmake .. && \
#     make && \
#     make install && \
#     ldconfig /usr/local/lib/ && \
#     echo "Micro-XRCE-DDS-Agent Installed"


# ── [COMMENTED] PX4-Autopilot v1.16.2: clone ────────────────
# Commentato per velocizzare il build durante lo sviluppo con OpenVINS.
# Decommentare quando si riattiva la simulazione SITL.
#
# RUN git clone https://github.com/PX4/PX4-Autopilot.git \
#         --branch v1.16.2 \
#         --recursive


# ── [COMMENTED] PX4: installa dipendenze Ubuntu ─────────────
#
# RUN cd /root/PX4-Autopilot && \
#     DEBIAN_FRONTEND=noninteractive bash ./Tools/setup/ubuntu.sh --no-nuttx


# ── [COMMENTED] PX4: build px4_sitl base ────────────────────
#
# RUN source /opt/ros/humble/setup.bash && \
#     cd /root/PX4-Autopilot && \
#     make px4_sitl && \
#     echo "PX4-Autopilot Installed"



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

RUN mkdir -p /root/colcon_ws/src && \
    cd /root/colcon_ws/src && \
    git clone https://github.com/rpng/open_vins.git


# ── OpenVINS: installing dependencies rosdep + build ─────────────
RUN source /opt/ros/humble/setup.bash && \
    apt-get update && \
    cd /root/colcon_ws && \
    rosdep install --from-paths src --ignore-src -r -y && \
    MAKEFLAGS="-j2" colcon build --symlink-install \
        --executor sequential \
        --packages-select ov_core ov_init ov_msckf ov_eval && \
    rm -rf /var/lib/apt/lists/*

# Limit parallelism to prevent OOM during build.
# --executor sequential: build one package at a time (ov_core → ov_init → ov_msckf → ov_eval).
# MAKEFLAGS="-j2": limit CMake to 2 threads per package.
# Without these flags, colcon spawns one GCC process per CPU core 
# each consuming ~1-2 GB RAM, which can exhaust system memory. I had out of memory issues on my pc with 8gb ram available causing vscode to crash.


# Source workspace OpenVINS in ogni sessione
RUN echo "source /root/colcon_ws/install/setup.bash" >> /root/.bashrc

### adding shortcuts for common commands --- run_px4_baylands_H1

# # starting the simulation without launching the gazebo interface
# RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\ncd /root/PX4-Autopilot\nHEADLESS=1 PX4_GZ_WORLD=baylands make px4_sitl gz_x500_depth\n' \
#     > /usr/local/bin/run_px4_baylands_H1 && \
#     chmod +x /usr/local/bin/run_px4_baylands_H1

# # executing the image bridge --- run_image_bridge
# RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge /world/baylands/model/x500_depth_0/link/camera_link/sensor/IMX214/image@sensor_msgs/msg/Image[gz.msgs.Image\n' \
#     > /usr/local/bin/run_image_bridge && \
#     chmod +x /usr/local/bin/run_image_bridge

# # executing the image bridge --- run_pointcloud_bridge

# RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nros2 run ros_gz_bridge parameter_bridge \\\n  /depth_camera/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked \\\n  /depth_camera@sensor_msgs/msg/Image[gz.msgs.Image \\\n  /camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo\n' \
#     > /usr/local/bin/run_pointcloud_bridge && \
#     chmod +x /usr/local/bin/run_pointcloud_bridge

# # ── Shortcut: run_all (background con &) ─────────────────────
# RUN printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nrun_image_bridge &\nrun_pointcloud_bridge &\nrun_px4_baylands_H1\n' \
#     > /usr/local/bin/run_1 && \
#     chmod +x /usr/local/bin/run_1

# ── Shortcut: run_setup_macos (runs the setup for macos environment) ─────────────────────
# RUN printf '#!/bin/bash\n\
#     apt-get update\n\
#     apt-get update && apt-get install -y libgl1-mesa-dri\n\
#     apt-get install -y xvfb mesa-utils libgl1-mesa-dri-\n\
#     apt-get update && apt-get install -y xvfb mesa-utils\n\
#     unset LIBGL_ALWAYS_INDIRECT\n\
#     export LIBGL_ALWAYS_SOFTWARE=1\n\
#     export GALLIUM_DRIVER=llvmpipe\n\' \
#     > /usr/local/bin/run_setup_macos && \
#     chmod +x /usr/local/bin/run_setup_macos

RUN printf '#!/bin/bash\n\
    set -e\n\
    unset LIBGL_ALWAYS_INDIRECT\n\
    export LIBGL_ALWAYS_SOFTWARE=1\n\
    export GALLIUM_DRIVER=llvmpipe\n\
    export GZ_IP=127.0.0.1\n\
    Xvfb :99 -screen 0 1280x1024x24 -ac +extension GLX +render -noreset &\n\
    XVFB_PID=$!\n\
    trap "kill $XVFB_PID" EXIT\n\
    sleep 2\n\
    export DISPLAY=:99\n\
    run_1\n' > /usr/local/bin/run_setup_macos && \
chmod +x /usr/local/bin/run_setup_macos

RUN printf '#!/bin/bash\n\
    source /opt/ros/humble/setup.bash\n\
    \n\
    # Configurazione forcing rendering software Mesa\n\
    unset LIBGL_ALWAYS_INDIRECT\n\
    export LIBGL_ALWAYS_SOFTWARE=1\n\
    export GALLIUM_DRIVER=llvmpipe\n\
    export MESA_GL_VERSION_OVERRIDE=3.3\n\
    \n\
    # Avvio di run_1 sotto server virtuale Xvfb con estensioni GLX per la telecamera\n\
    xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24 +extension GLX +render -noreset" run_1\n' \
> /usr/local/bin/run_1_macos && \
chmod +x /usr/local/bin/run_1_macos


CMD ["bash", "-c", "tmux new-session -A -s main"]