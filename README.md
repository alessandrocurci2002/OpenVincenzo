# ROS 2 Humble + OpenVINS Docker Environment

Docker setup for running [OpenVINS](https://github.com/rpng/open_vins) on ROS 2 Humble (Ubuntu 22.04), with support for Gazebo Harmonic and PX4 SITL (currently disabled for faster builds during dataset evaluation).

***

## Repository Structure

```
.
├── Dockerfile          # Image definition: ROS 2 Humble + GStreamer + Gazebo Harmonic + OpenVINS
└── start_ros.sh        # Helper script to launch the container with X11 forwarding and dataset mount
```

***

## Stack

| Component | Version / Notes |
|---|---|
| Base image | `osrf/ros:humble-desktop-full` (Ubuntu 22.04) |
| ROS 2 | Humble Hawksbill |
| Gazebo | Harmonic (via OSRF apt repo) |
| GStreamer | 1.0 (dev + plugins) |
| OpenVINS | Latest `main` from [rpng/open_vins](https://github.com/rpng/open_vins) |
| Ceres Solver | System package (`libceres-dev`) |
| PX4 Autopilot | v1.16.2 — **commented out** |
| Micro-XRCE-DDS-Agent | v2.4.3 — **commented out** |

***

## Prerequisites

- Docker installed and running
- A host machine running Linux with X11 (for GUI / RViz2)
- A `~/datasets/` folder on the host containing ROS 2 bag files (e.g. EuRoC sequences converted from ROS 1)

### Converting EuRoC bags from ROS 1 → ROS 2

```bash
# Install a Humble-compatible version of rosbags
pip3 install "rosbags==0.9.19"

# Convert (positional argument, no --src flag)
rosbags-convert /path/to/V1_01_easy.bag --dst ~/datasets/V1_01_easy
```

***

## Building the Image

```bash
docker build -t ov_humble .
```

> **Note on build time and RAM:** OpenVINS is compiled inside the image with parallelism intentionally limited (`MAKEFLAGS="-j2"`, `--executor sequential`) to avoid OOM errors on machines with ≤8 GB RAM. On such systems, a standard parallel colcon build can cause the system to run out of memory and crash VS Code or other applications.

***

## Running the Container

Use the provided helper script:

```bash
chmod +x start_ros.sh
./start_ros.sh <container_name> <image_name>

# Example
./start_ros.sh ov_container ov_humble
```

The script:
1. Grants X11 access to the container (`xhost +local:root`)
2. Creates a secure `.docker.xauth` file for X forwarding
3. Runs the container with:
   - GUI forwarding (`DISPLAY`, `XAUTHORITY`, `/tmp/.X11-unix`)
   - `--net=host` for ROS 2 DDS discovery
   - `--privileged` for hardware access
   - Bind mount of `~/datasets` → `/datasets` inside the container
   - `GZ_IP=127.0.0.1` and `ROS_DOMAIN_ID=0` preset

The container starts a `tmux` session named `main`.

***

## Running OpenVINS on a Dataset

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

## Re-enabling PX4 + Micro-XRCE-DDS (SITL mode)

All PX4-related sections in the `Dockerfile` are marked `[COMMENTED]`. To restore the full SITL stack:

1. Uncomment the `[COMMENTED]` blocks in the `Dockerfile` (Micro-XRCE-DDS-Agent, PX4 clone, `ubuntu.sh`, `make px4_sitl`, and the bridge shortcuts)
2. Rebuild the image:
   ```bash
   docker build -t px4_humble .
   ```
3. Launch with the same `start_ros.sh` script

***

## Differences vs. the Official OpenVINS Docker Guide

The [official OpenVINS Docker guide](https://docs.openvins.com/dev-docker.html) uses a minimal approach: the source code is **not baked into the image**. Instead, the workspace is bind-mounted at runtime and built manually inside the container each time. This keeps the image small and flexible, but requires an extra manual build step on every fresh container.

This setup diverges from the official guide in several ways:

| Aspect | Official guide (`Dockerfile_ros2_22_04`) | This Dockerfile |
|---|---|---|
| **OpenVINS source** | Bind-mounted at runtime (`--mount`) | Cloned and built inside the image |
| **Build step** | Manual (`colcon build` inside container) | Baked into `docker build` |
| **Resulting image size** | Smaller (no compiled artifacts) | Larger (~3–4 GB extra for build products) |
| **RAM protection** | None — may OOM on low-RAM systems | `MAKEFLAGS="-j2"` + sequential executor |
| **Reproducibility** | Depends on the host workspace state | Fully self-contained and reproducible |
| **SSH / CLion debug** | Included in official Dockerfile | Omitted (not needed for dataset runs) |
| **Additional stack** | ROS 2 Humble only | + GStreamer + Gazebo Harmonic |
| **PX4 / XRCE-DDS** | Not present | Present but commented out |
| **X11 forwarding** | Not scripted | Automated via `start_ros.sh` |
| **Dataset mount** | Manual `docker run` flags | Automated via `start_ros.sh` |

The key trade-off: this image takes longer to build but starts instantly with no manual compilation required, which is convenient for iterative dataset evaluation.

***

## Environment Variables Set at Runtime

| Variable | Value | Purpose |
|---|---|---|
| `DISPLAY` | from host | X11 GUI forwarding |
| `QT_X11_NO_MITSHM` | `1` | Fix Qt shared memory issue in Docker |
| `XAUTHORITY` | `/tmp/.docker.xauth` | X11 authentication |
| `GZ_IP` | `127.0.0.1` | Force Gazebo to bind on loopback |
| `ROS_DOMAIN_ID` | `0` | ROS 2 DDS domain isolation |