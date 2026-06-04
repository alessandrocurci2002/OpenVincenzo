# ROS 2 Humble + PX4 SITL + OpenVINS — Docker Environment

A Docker environment for UAV simulation with visual-inertial odometry support. Combines ROS 2 Humble, Gazebo Harmonic, PX4-Autopilot SITL (stereo fork), OpenVINS, and Micro-XRCE-DDS-Agent.

***

## Stack

| Component             | Version / Source                                                    |
|-----------------------|---------------------------------------------------------------------|
| ROS 2                 | Humble (desktop-full)                                               |
| Gazebo                | Harmonic                                                            |
| PX4-Autopilot         | `FedericoDD/PX4-Autopilot` @ `v1.16.2-stereo` (host submodule)     |
| OpenVINS              | `rpng/open_vins` (built in `/root/colcon_ws`)                       |
| Micro-XRCE-DDS-Agent  | v2.4.3                                                              |
| Ceres Solver          | via `apt` (`libceres-dev`)                                          |
| Base OS               | Ubuntu 22.04 (Jammy)                                                |

***

## Repository Structure

```
.
├── Dockerfile
├── dockerRun.sh
├── .gitmodules
└── PX4-Autopilot/        ← git submodule, must exist on host before running
```

***

## PX4-Autopilot — Host Setup

PX4 is **not cloned inside the Docker image**. It is provided as a git submodule on the host and mounted into the container at runtime.

`.gitmodules`:
```ini
[submodule "PX4-Autopilot"]
    path   = PX4-Autopilot
    url    = https://github.com/FedericoDD/PX4-Autopilot.git
    branch = v1.16.2-stereo
```

Initialize the submodule before building or running the container:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

If the submodule is already present but on the wrong commit:

```bash
cd PX4-Autopilot
git checkout v1.16.2-stereo
git submodule update --init --recursive
cd ..
```

***

## Stack

**Base tools** — `git`, `cmake`, `build-essential`, `tmux`, `openssh-server`, `gdb`, Python 3 dev stack, `libeigen3-dev`.

**GStreamer** — full plugin set (`good`, `bad`, `ugly`, `libav`) for camera stream handling.

**Gazebo Harmonic** — installed from the OSRF repository. Includes `ros-humble-ros-gzharmonic` for ROS 2 ↔ Gazebo bridging.

**Ceres Solver** — installed via `apt` (`libceres-dev`, `libgoogle-glog-dev`, `libsuitesparse-dev`, `libopenblas-dev`).

**Micro-XRCE-DDS-Agent v2.4.3** — built from source. Acts as the DDS agent between the PX4 uXRCE-DDS client and ROS 2.

**OpenVINS** — cloned into `/root/colcon_ws/src/open_vins`. Built with `colcon` (packages: `ov_core`, `ov_init`, `ov_msckf`, `ov_eval`). Dependencies installed via `rosdep`.

**PX4-Autopilot** — mounted from the host at `/root/PX4-Autopilot`. PX4 Ubuntu dependencies (`Tools/setup/ubuntu.sh --no-nuttx`) are installed at container startup, not at image build time.

**open_vins** — cloned into `/root/colcon_ws/src/open_vins`: git clone https://github.com/alessandrocurci2002/OpenVins_StereocameraPX4.git colcon_ws/src/open_vins.Built with `colcon` (packages: `ov_core`, `ov_init`, `ov_msckf`, `ov_eval`). Dependencies installed via `rosdep`

**CLion remote debug** — `sshd` configured and started at container launch. A `user/password` account is available for CLion toolchain access.

***

## Shortcut Commands

Available in any shell inside the container (`/usr/local/bin/`):

| Command                  | Description                                                          |
|--------------------------|----------------------------------------------------------------------|
| `run_px4_baylands_H1`    | Starts PX4 SITL — `baylands` world, `gz_x500_depth`, headless       |
| `run_image_bridge`       | ROS ↔ Gazebo bridge for IMX214 RGB image                             |
| `run_image_bridge_left`  | Bridge for left stereo camera image                                  |
| `run_image_bridge_right` | Bridge for right stereo camera image                                 |
| `run_pointcloud_bridge`  | Bridge for depth pointcloud, depth image, and camera info            |
| `run_1`                  | Starts all bridges in background, then PX4 in foreground             |

### Topic Mapping

Full Gazebo topic prefix: `/world/baylands/model/x500_depth_0/link/camera_link`

| ROS 2 Topic                        | Type                           | Sensor               |
|------------------------------------|--------------------------------|----------------------|
| `.../sensor/IMX214/image`          | `sensor_msgs/msg/Image`        | RGB camera           |
| `.../sensor/left_camera/image`     | `sensor_msgs/msg/Image`        | Left stereo camera   |
| `.../sensor/right_camera/image`    | `sensor_msgs/msg/Image`        | Right stereo camera  |
| `/depth_camera/points`             | `sensor_msgs/msg/PointCloud2`  | Depth camera         |
| `/depth_camera`                    | `sensor_msgs/msg/Image`        | Depth image          |
| `/camera_info`                     | `sensor_msgs/msg/CameraInfo`   | Camera info          |

***

## Prerequisites

- Docker installed on the host
- Linux host with X11 (required for Gazebo GUI; not needed in headless mode)
- `xauth` installed on the host
- `PX4-Autopilot/` submodule initialized on the host (see above)

***

## Build

```bash
# Install a Humble-compatible version of rosbags
pip3 install "rosbags==0.9.19"

The build installs Gazebo Harmonic, Micro-XRCE-DDS-Agent, and the OpenVINS workspace. Expect 20–40 minutes on the first build.

***

## Run

```bash
chmod +x ./dockerRun.sh
./dockerRun.sh <container_name> <image_name>
```

`dockerRun.sh` mounts `./PX4-Autopilot` into the container at `/root/PX4-Autopilot`, forwards the X11 display, and sets the required environment variables.

At startup the container will:
1. Start `sshd`
2. Run `Tools/setup/ubuntu.sh --no-nuttx` from the mounted PX4 tree
3. Open a `tmux` session named `main`

***

## Usage Inside the Container

## Full launch (headless)

```bash
run_1
```

### Step-by-step

```bash
# PX4 SITL
run_px4_baylands_H1

# Bridges (each in a separate tmux pane)
run_image_bridge
run_image_bridge_left
run_image_bridge_right
run_pointcloud_bridge
```

## DDS Agent

```bash
MicroXRCEAgent udp4 -p 8888
```

## OpenVINS workspace

```bash
source /opt/ros/humble/setup.bash
source /root/colcon_ws/install/setup.bash
```

### Running OpenVINS on a Dataset

Once inside the container, both the ROS 2 and OpenVINS workspaces are already sourced via `.bashrc`.

### EuRoC MAV — monocular + IMU

```bash
ros2 launch ov_msckf subscribe.launch.py \
    config:=euroc_mav \
    bag:=/datasets/V1_01_easy \
    bag_start:=0
```


### Visualize in RViz2

Open a second tmux pane (`Ctrl+b "`) and run:

```bash
rviz2 -d /root/colcon_ws/src/open_vins/ov_msckf/launch/display.rviz
```

### Evaluate results

```bash
ros2 run ov_eval plot_consistency \
    /root/colcon_ws/src/open_vins/ov_eval/data/tumvi.txt
```

***

## Environment Variables (injected by `dockerRun.sh`)

| Variable           | Value                |
|--------------------|----------------------|
| `DISPLAY`          | Inherited from host  |
| `QT_X11_NO_MITSHM` | `1`                  |
| `XAUTHORITY`       | `/tmp/.docker.xauth` |
| `GZ_IP`            | `127.0.0.1`          |
| `ROS_DOMAIN_ID`    | `0`                  |

***

## Running the Container

- `--net=host` and `--privileged` are required for PX4 ↔ ROS 2 DDS communication.
- Since `PX4-Autopilot` is mounted from the host, Git operations inside the container affect the host checkout. Keep file ownership consistent to avoid `root`-owned `.git` files.
- Headless mode (`HEADLESS=1`) skips Gazebo rendering — use it on machines without a GPU.
- Re-attach to a running container: `docker exec -it <container_name> bash`
