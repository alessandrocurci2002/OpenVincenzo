# ROS 2 Humble + PX4 SITL — Docker Environment

A self-contained Docker environment for UAV simulation combining **ROS 2 Humble**, **Gazebo Harmonic**, **PX4-Autopilot SITL**, and **Micro-XRCE-DDS-Agent**. Designed for depth-camera equipped drone simulation (`x500_depth`) with full ROS ↔ Gazebo sensor bridging.

***

## Stack

| Component | Version |
|---|---|
| ROS 2 | Humble (desktop-full) |
| Gazebo | Harmonic |
| PX4-Autopilot | v1.16.2 |
| Micro-XRCE-DDS-Agent | v2.4.3 |
| Base OS | Ubuntu 22.04 (Jammy) |

***

## Repository Structure

```
.
├── Dockerfile        # Defines the Docker image
└── dockerRun.sh      # Script to launch the container with X11 GUI support
```

***

## What's Inside the Image

### Base Dependencies
Standard build tools, `git`, `cmake`, `wget`, `curl`, `python3-pip`, and `tmux` for multiplexed terminal sessions inside the container.

### GStreamer
Full GStreamer pipeline support (`good`, `bad`, `ugly`, `libav` plugins) for camera stream processing.

### Gazebo Harmonic
Installed from the official OSRF repository, with the `ros-humble-ros-gzharmonic` bridge package for seamless ROS 2 ↔ Gazebo topic communication.

### Micro-XRCE-DDS-Agent
Built from source at tag `v2.4.3`. Acts as the DDS middleware agent between the PX4 uXRCE-DDS client and ROS 2.

### PX4-Autopilot SITL
Cloned at tag `v1.16.2` with all submodules. Ubuntu dependencies installed via the official `Tools/setup/ubuntu.sh` script. The `px4_sitl` target is pre-compiled at image build time to speed up the first launch.

***

## Shortcut Commands

These scripts are installed in `/usr/local/bin/` and are callable directly from any shell session inside the container.

| Command | Description |
|---|---|
| `run_px4_baylands_H1` | Starts PX4 SITL with the `baylands` world and `x500_depth` model in **headless mode** (no Gazebo GUI) |
| `run_image_bridge` | Launches the ROS ↔ Gazebo bridge for the IMX214 RGB camera image topic |
| `run_pointcloud_bridge` | Launches the bridge for pointcloud, depth image, and camera info topics |
| `run_1` | Starts all three commands above: bridges in background (`&`), PX4 in foreground |

### Topic Mapping

**Image bridge** (`run_image_bridge`):
```
/world/baylands/model/x500_depth_0/link/camera_link/sensor/IMX214/image
  → sensor_msgs/msg/Image
```

**Pointcloud bridge** (`run_pointcloud_bridge`):
```
/depth_camera/points        → sensor_msgs/msg/PointCloud2
/depth_camera               → sensor_msgs/msg/Image
/camera_info                → sensor_msgs/msg/CameraInfo
```

***

## Prerequisites

- Docker installed and running on the host
- Linux host with X11 (for GUI support, if not using headless mode)
- `xauth` installed on the host

***

## Build the Image

```bash
docker build -t <image_name> .
```

> ⚠️ The build takes approximately **15–30 minutes** as it compiles PX4, Micro-XRCE-DDS-Agent, and downloads Gazebo Harmonic.

***

## Run the Container

### 1. Make the script executable

```bash
chmod +x ./dockerRun.sh
```

### 2. Launch the container

```bash
./dockerRun.sh <container_name> <image_name>
```

**Example:**

```bash
./dockerRun.sh px4_sim ros2_px4_image
```

The script will:
- Grant X11 access from root (`xhost +local:root`)
- Generate a `/tmp/.docker.xauth` file with the correct X11 credentials
- Start the container with host networking, display forwarding, and pre-configured ROS/Gazebo environment variables

***

## Inside the Container

The default entry point opens a `tmux` session named `main`. You can open new panes with `Ctrl+B` then `%` (vertical split) or `"` (horizontal split).

### Quick full launch (headless)

```bash
run_1
```

### Manual step-by-step launch

```bash
# Terminal 1 – PX4 SITL
run_px4_baylands_H1

# Terminal 2 – Image bridge
run_image_bridge

# Terminal 3 – Pointcloud bridge
run_pointcloud_bridge
```

### Start the Micro-XRCE-DDS-Agent (if needed separately)

```bash
MicroXRCEAgent udp4 -p 8888
```

***

## Environment Variables

These are automatically injected by `dockerRun.sh`:

| Variable | Value |
|---|---|
| `DISPLAY` | Inherited from host |
| `QT_X11_NO_MITSHM` | `1` |
| `XAUTHORITY` | `/tmp/.docker.xauth` |
| `GZ_IP` | `127.0.0.1` |
| `ROS_DOMAIN_ID` | `0` |

***

## Notes

- The container uses `--net=host` and `--privileged`: required for DDS communication between PX4 and ROS 2 on the same host.
- Headless mode (`HEADLESS=1`) disables Gazebo rendering, reducing computational load — useful for development on machines without a dedicated GPU.
- To re-attach to a running container: `docker exec -it <container_name> bash`