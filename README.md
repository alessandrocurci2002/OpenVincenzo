# ROS 2 Humble + PX4 SITL + OpenVINS — Docker Environment

A Docker environment for UAV simulation with visual-inertial odometry support. Combines ROS 2 Humble, Gazebo Harmonic, PX4-Autopilot SITL (stereo fork), OpenVINS, and Micro-XRCE-DDS-Agent.

***

## Stack

| Component             | Version / Source                                                    |
|-----------------------|---------------------------------------------------------------------|
| ROS 2                 | Humble (`ros-base` + explicit RViz2)                                |
| Gazebo                | Harmonic                                                            |
| PX4-Autopilot         | `FedericoDD/PX4-Autopilot` @ `v1.16.2-stereo` (host submodule)     |
| OpenVINS              | `rpng/open_vins` (built in `/root/colcon_ws`)                       |
| Micro-XRCE-DDS-Agent  | v2.4.3                                                              |
| Ceres Solver          | via `apt` (`libceres-dev`)                                          |
| OAK-D Pro profile     | Optional Docker target `oak`, DepthAI ROS v3                        |
| Base OS               | Ubuntu 22.04 (Jammy)                                                |

***

## Repository Structure

```
.
├── Dockerfile
├── dockerRun.sh
├── dockerRun_oak.sh
├── scripts/
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

## What's Inside the Image

**Base tools** — `git`, `cmake`, `build-essential`, `tmux`, `openssh-server`, `gdb`, Python 3 dev stack, `libeigen3-dev`, `colcon`, `rosdep`.

**RViz2** — installed explicitly with `ros-humble-rviz2`, without depending on the `desktop-full` image.

**GStreamer** — full plugin set (`good`, `bad`, `ugly`, `libav`) for camera stream handling.

**Gazebo Harmonic** — installed from the OSRF repository. Includes `ros-humble-ros-gz-bridge` for the dedicated stereo/IMU bridge wrappers.

**Ceres Solver** — installed via `apt` (`libceres-dev`, `libgoogle-glog-dev`, `libsuitesparse-dev`, `libopenblas-dev`).

**Micro-XRCE-DDS-Agent v2.4.3** — built from source. Acts as the DDS agent between the PX4 uXRCE-DDS client and ROS 2.

**OpenVINS** — mounted from the host into `/root/colcon_ws/src/open_vins`. Built at container startup with `colcon` (packages: `ov_core`, `ov_init`, `ov_msckf`, `ov_eval`) unless `BUILD_OPENVINS=0`. The build, install, and log directories are persisted in Docker volumes.

**PX4-Autopilot** — mounted from the host at `/root/PX4-Autopilot`. PX4 Ubuntu dependencies (`Tools/setup/ubuntu.sh --no-nuttx`) are installed at container startup, not at image build time.

**CLion remote debug** — `sshd` configured and started at container launch. A `user/password` account is available for CLion toolchain access.

**OAK-D Pro support** — optional `oak` target installs `ros-humble-depthai-ros-v3`. The default production image does not enable the ROS testing repository or install DepthAI packages.

***

## Shortcut Commands

Available in any shell inside the container (`/usr/local/bin/`):

| Command                  | Description                                                          |
|--------------------------|----------------------------------------------------------------------|
| `run_px4_baylands_H1`    | Starts PX4 SITL — `baylands` world, `gz_x500_depth`, headless; exports the PX4 Gazebo plugin path |
| `run_gz_stereo_bridge`   | Waits for real Gazebo topics, then bridges left/right stereo images and IMU to ROS |
| `run_image_bridge`       | Convenience wrapper for the IMX214 RGB image bridge                  |
| `run_image_bridge_left`  | Convenience wrapper for the left stereo camera image bridge          |
| `run_image_bridge_right` | Convenience wrapper for the right stereo camera image bridge         |
| `run_pointcloud_bridge`  | Disabled for the OpenVINS stereo flow; use `run_gz_stereo_bridge`    |
| `run_1`                  | Starts the optional stereo/IMU bridge, then PX4 `gz_x500_depth` in the `baylands` world |
| `setup_px4_repo`         | Clones/updates the mounted PX4 fork recursively in `/root/PX4-Autopilot` |
| `setup_px4_deps`         | Runs PX4 `Tools/setup/ubuntu.sh --no-nuttx` inside the container; skips unavailable multilib packages on arm64 |

PX4 should normally be initialized on the host, because `/root/PX4-Autopilot` is a bind mount:

```bash
git submodule update --init --recursive PX4-Autopilot
```

If you intentionally want to bootstrap it from inside the container:

```bash
setup_px4_repo
setup_px4_deps
```

If `setup_px4_repo` is run inside the container, files are written through the bind mount and may become owned by `root` on the host.

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
# Default production image, no OAK-D Pro driver
docker build --target production -t openvincenzo:humble .

# OAK-D Pro image
docker build --target oak -t openvincenzo:humble-oak .
```

The build installs Gazebo Harmonic, Micro-XRCE-DDS-Agent, RViz2, and runtime tools. OpenVINS is built at container startup when the host workspace is mounted. Expect 20–40 minutes on the first build.

### Makefile Quick Start

For day-to-day use, the Makefile wraps the Docker commands:

```bash
sudo apt install make
make help
make build
make smoke
make build-oak
make smoke-oak
make oak-stereo
```

For the first local run, build the image before starting a container:

```bash
make setup-px4-host
sudo make build
sudo make run
```

Common overrides:

```bash
make run RUN_PX4_SETUP=0 BUILD_OPENVINS=0
make run-full
make run-full GZ_BRIDGE_STREAMS=left,right,imu
make shell-full
make build IMAGE=my-openvincenzo:dev
make smoke-bridge
make oak-stereo OAK_LAUNCH_FILE=driver.launch.py
```

The Makefile sets `BUILDX_GIT_INFO=0` for Docker builds to avoid Buildx warnings when the build context is copied without a usable `.git` directory. The CI still tags images from the GitHub commit SHA.

### CI/CD

GitHub Actions builds one Docker workflow per public image target and runs image smoke checks for both amd64 and arm64:

- `Docker production`: builds `--target production`
- `Docker OAK-D Pro`: builds `--target oak`

Pull requests build without pushing. Pushes to `main`, `master`, or tags matching `v*` publish multi-arch images to GHCR:

```text
ghcr.io/<owner>/<repo>:production
ghcr.io/<owner>/<repo>:production-<sha>
ghcr.io/<owner>/<repo>:oak
ghcr.io/<owner>/<repo>:oak-<sha>
```

Manual runs can be started from the GitHub Actions tab; set `push_image=true` to publish the image.

### Raspberry Pi 5 / ARM64

On the Raspberry Pi 5, build natively:

```bash
docker build --target production -t openvincenzo:humble-arm64 .
docker build --target oak -t openvincenzo:humble-oak-arm64 .
```

From an amd64 workstation, cross-build with buildx:

```bash
docker buildx build --platform linux/arm64/v8 --target production -t openvincenzo:humble-arm64 --load .
docker buildx build --platform linux/arm64/v8 --target oak -t openvincenzo:humble-oak-arm64 --load .
```

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

Runtime setup can be controlled with environment variables:

```bash
RUN_PX4_SETUP=0 BUILD_OPENVINS=0 ./dockerRun.sh ov-test openvincenzo:humble smoke_no_oak
```

Use `RUN_PX4_SETUP=0` after PX4 dependencies are already present in the image/container layer or when running image-only smoke tests. Use `BUILD_OPENVINS=0` to skip rebuilding the mounted OpenVINS workspace. Use `FORCE_BUILD_OPENVINS=1` when the persisted OpenVINS install volume must be rebuilt from source.

### Smoke Test Without OAK-D Pro

```bash
RUN_PX4_SETUP=0 BUILD_OPENVINS=0 ./dockerRun.sh ov-smoke openvincenzo:humble smoke_no_oak
```

This validates ROS 2, RViz2, Gazebo bridge, Micro-XRCE-DDS-Agent, and optional OpenVINS packages if they have already been built.

### OAK-D Pro Host Setup

On the Raspberry Pi host, install the Luxonis udev rule once:

```bash
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="03e7", MODE="0666"' | sudo tee /etc/udev/rules.d/80-movidius.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

For OAK-D Pro, prefer external power or a powered USB3 hub. The Pro models can draw more current than a Raspberry Pi USB port can reliably supply under load.

### Smoke Test With OAK-D Pro

```bash
chmod +x ./dockerRun_oak.sh
RUN_PX4_SETUP=0 BUILD_OPENVINS=0 ./dockerRun_oak.sh ov-oak-smoke openvincenzo:humble-oak smoke_oak
```

The test checks the DepthAI ROS v3 driver package, verifies a Luxonis USB device with vendor id `03e7`, launches the OAK driver, and confirms camera topics appear.

### Live OAK-D Pro Stereo Driver

```bash
./dockerRun_oak.sh ov-oak openvincenzo:humble-oak run_oak_stereo
```

By default `run_oak_stereo` launches `rgbd_pcl.launch.py`. Override the launch file or pass launch arguments when needed:

```bash
OAK_LAUNCH_FILE=driver.launch.py ./dockerRun_oak.sh ov-oak openvincenzo:humble-oak run_oak_stereo use_rviz:=true
```

***

## Usage Inside the Container

## Full launch (headless)

```bash
RUN_ROS_GZ_BRIDGES=1 run_1
```

`make run-full` already sets `RUN_ROS_GZ_BRIDGES=1`.

### Step-by-step

```bash
# PX4 SITL
run_px4_baylands_H1

# Stereo images + IMU bridge in a separate tmux pane
run_gz_stereo_bridge
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
| `RUN_PX4_SETUP`    | `1` by default in `entrypoint.sh`; Makefile defaults to `0` |
| `BUILD_OPENVINS`   | `1` by default in `entrypoint.sh`; Makefile defaults to `0` |
| `FORCE_BUILD_OPENVINS` | `0`; set to `1` to rebuild the persisted OpenVINS workspace |
| `RUN_ROS_GZ_BRIDGES` | `0`; `make run-full` sets it to `1` |
| `GZ_BRIDGE_STREAMS` | `left,right,imu` by default |
| `GZ_MODEL_NAME`    | `x500_depth_0` by default |

***

## Notes

- `--net=host` and `--privileged` are required for PX4 ↔ ROS 2 DDS communication.
- `dockerRun_oak.sh` also maps `/dev/bus/usb` and `/run/udev` so DepthAI can access the OAK-D Pro.
- Since `PX4-Autopilot` is mounted from the host, Git operations inside the container affect the host checkout. Keep file ownership consistent to avoid `root`-owned `.git` files.
- The PX4 Gazebo patch is applied by `make setup-px4-host` / `make patch-px4-gz-host`, not by the container entrypoint.
- `dockerRun.sh` and `dockerRun_oak.sh` persist `/root/colcon_ws/build`, `/root/colcon_ws/install`, and `/root/colcon_ws/log` in Docker volumes.
- Headless mode (`HEADLESS=1`) skips Gazebo rendering — use it on machines without a GPU.
- Re-attach to a running container: `docker exec -it <container_name> bash`
