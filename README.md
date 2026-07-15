# ROS 2 Humble + OpenVINS + DepthAI — Docker Environment

A Docker environment for OAKDPRO with ROS 2 Humble, OpenVINS, and DepthAI support. PX4 is no longer used.

***

## Stack

| Component             | Version / Source                                                    |
|-----------------------|---------------------------------------------------------------------|
| ROS 2                 | Humble (desktop-full)                                               |
| Gazebo                | Harmonic                                                            |
| OpenVINS              | built in `/root/colcon_ws`                                          |
| DepthAI               | built in `/root/depthai-ws`                                         |
| Ceres Solver          | via `apt` (`libceres-dev`)                                          |
| Base OS               | Ubuntu 22.04 (Jammy)                                                |

***

## Repository Structure

```
.
├── Dockerfile
├── dockerRun.sh
├── entrypoint.sh        ← builds depthai and OpenVINS inside the container
├── Makefile             ← launch shortcuts for DepthAI and OpenVINS
├── depthai-ws/
│   └── src/
│       ├── depthai-core/
│       └── depthai-ros/
└── colcon_ws/
    └── src/
        └── open_vins/
```

***

## DepthAI Workspace

- `depthai-ws/src/depthai-core`
- `depthai-ws/src/depthai-ros`
- `entrypoint.sh` installs dependencies and builds the `depthai-ws` workspace with `colcon`
- after build, the workspace is sourced from `/root/depthai-ws/install/setup.bash`

***

## OpenVINS Workspace

- `colcon_ws/src/open_vins`
- built in `entrypoint.sh` after DepthAI
- packages built: `ov_core`, `ov_init`, `ov_msckf`, `ov_eval`

***

## Makefile Targets

Use the Makefile inside the container after sourcing the ROS environment.

- `make depthai` — launch `depthai_ros_driver_v3` with rectified stereo streams
- `make depthai-rectified` — launch only rectified infrared streams
- `make openvins` — launch the OpenVINS example subscriber

***

## Build

```bash
docker build -t <image_name> .
```

The build installs the required ROS and DepthAI components, then builds the workspace.

***

## Run

```bash
chmod +x ./dockerRun.sh
./dockerRun.sh <container_name> <user> <host>
```

Inside the container, use the Makefile targets to launch DepthAI and OpenVINS.

***

## Prerequisites

- Docker installed on the host
- Linux host with X11 if GUI mode is required
- `xauth` installed on the host
- `git submodule update --init --recursive` if required by repo dependencies
