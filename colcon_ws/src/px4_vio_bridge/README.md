# px4_vio_bridge

Bridges OpenVINS's `odomimu` output (`nav_msgs/Odometry`) into PX4's
`VehicleOdometry` (`px4_msgs/msg/VehicleOdometry`), so the uXRCE-DDS client
running on PX4 can fuse it into EKF2 as vision odometry.

```
ov_msckf (OpenVINS)  --/ov_msckf/odomimu-->  vio_to_px4_bridge  --/fmu/in/vehicle_visual_odometry-->  PX4 (uXRCE-DDS client)
   nav_msgs/Odometry           (this package)          px4_msgs/msg/VehicleOdometry
```

See [CLAUDE.md](../../../CLAUDE.md) for the project-wide context (hardware,
network, PX4/EKF2 setup). This README only covers this one node.

## Why a bridge is needed

OpenVINS and PX4 don't speak the same frames or the same DDS QoS:

- **Message type**: OpenVINS publishes ROS's generic `nav_msgs/Odometry`;
  PX4 only understands its own `px4_msgs/msg/VehicleOdometry`.
- **World frame**: OpenVINS's `global` frame is gravity-aligned, **z-up**,
  x = the vehicle's heading at initialisation. PX4's `POSE_FRAME_FRD` is the
  same kind of frame (arbitrary heading, fixed at init) but **z-down**. Fixed
  180 deg rotation about x, always the same, not configurable.
- **Body frame**: OpenVINS reports IMU-frame quantities (velocity, angular
  velocity) using the physical axes of the sensor that produced them — for
  the OAK-D Pro, that's ~camera-optical axes (x-right, y-down, z-forward),
  *not* the drone's FRD body frame. This one **is** mounting-dependent, see
  below.
- **QoS**: PX4's uXRCE-DDS client subscribes `BEST_EFFORT`. ROS 2's default
  is `RELIABLE`. A `RELIABLE` publisher on `/fmu/in/vehicle_visual_odometry`
  means messages get silently dropped, no error anywhere.
- **Timestamps**: PX4/EKF2 uses `timestamp_sample` to compensate for the
  vision-to-IMU delay (`EKF2_EV_DELAY`). If the bridge stamped messages with
  its own wall-clock time instead of the time the sample was actually taken,
  any scheduling jitter of the bridge node itself would look to EKF2 like a
  physical delay in the camera pipeline. **This node always uses
  `msg.header.stamp` from the incoming OpenVINS message, never
  `self.get_clock().now()`.**

## What it does

For every `odomimu` message (published by OpenVINS at IMU rate, ~192 Hz in
this project's config, once the filter is initialised):

| OpenVINS (`odomimu`) | → | PX4 (`VehicleOdometry`) |
|---|---|---|
| `pose.pose.position` (global, z-up) | fixed 180° flip about x | `position` (`POSE_FRAME_FRD`) |
| `pose.pose.orientation` (Hamilton, ROS xyzw) | world flip + IMU→body rotation | `q` (Hamilton, PX4 wxyz) |
| `twist.twist.linear` (already IMU-frame) | `imu_to_body_rotation_deg` | `velocity` (`VELOCITY_FRAME_BODY_FRD`) |
| `twist.twist.angular` (already IMU-frame) | `imu_to_body_rotation_deg` | `angular_velocity` |
| `pose.covariance` / `twist.covariance` diagonal blocks | same rotations | `position_variance` / `orientation_variance` / `velocity_variance` |
| `header.stamp` | µs since epoch | `timestamp` **and** `timestamp_sample` |

`reset_counter` is currently always `0`: OpenVINS's `odomimu` topic carries
no re-initialisation signal, so the bridge cannot detect a filter reset yet.
If you add a way to detect that (e.g. watching for a discontinuity, or a
future OpenVINS status topic), bump `reset_counter` there — EKF2 uses it to
know the vision origin jumped.

## The IMU → drone body rotation (`imu_to_body_rotation_deg`)

This is the one parameter you are expected to tune for your own airframe. It
is **not** the camera-to-IMU calibration (that's `T_cam_imu` in OpenVINS's
own `kalibr_imucam_chain.yaml` and is unrelated to PX4) — it is the rotation
between the OpenVINS IMU's physical axes and the Pixhawk's FRD body axes.

Given as Euler angles in degrees, applied as `R = Rz(yaw) · Ry(pitch) ·
Rx(roll)` (aerospace ZYX convention). The default `[90.0, 0.0, 90.0]`
corresponds to:

```
FRD_forward = IMU_z   FRD_right = IMU_x   FRD_down = IMU_y
```

which is exactly the OAK-D Pro optical-to-IMU axis permutation confirmed
from this project's real calibration (`T_cam_imu` for cam0 in
`colcon_ws/src/open_vins/config/oakdpro_calib05_newImucalib/kalibr_imucam_chain.yaml`
has a rotation block that is ~identity — i.e. the OAK-D Pro's IMU axes
coincide with its left camera's optical axes). **This default is only
correct if the OAK-D Pro is mounted level and forward-facing on the
airframe.** If your physical mounting has any additional tilt or rotation
relative to the Pixhawk, measure it and compose it into these three angles —
the parameter must describe the true IMU-to-drone-body rotation, not just
the sensor's internal one.

The world-frame flip (`global` z-up → `POSE_FRAME_FRD` z-down) is **not**
exposed as a parameter: it's fixed by the PX4 message convention, not a
calibration value.

## Parameters (`config/vio_bridge.yaml`)

| Parameter | Default | Meaning |
|---|---|---|
| `input_topic` | `/ov_msckf/odomimu` | OpenVINS odometry topic to subscribe to |
| `output_topic` | `/fmu/in/vehicle_visual_odometry` | PX4 input topic |
| `input_qos_reliability` | `reliable` | QoS to *subscribe* with; must be compatible with OpenVINS's publisher (currently `RELIABLE`) |
| `input_qos_depth` | `10` | subscriber queue depth |
| `output_qos_depth` | `5` | publisher queue depth (reliability is hardcoded `BEST_EFFORT`, see above) |
| `imu_to_body_rotation_deg` | `[90.0, 0.0, 90.0]` | `[roll, pitch, yaw]` degrees, OpenVINS-IMU → drone-body-FRD, see above |

## Running it

Build (inside the container, alongside the other workspaces):

```bash
cd colcon_ws && colcon build --packages-select px4_vio_bridge
source install/setup.bash
```

Launch (after OpenVINS and the uXRCE-DDS agent are already running):

```bash
ros2 launch px4_vio_bridge vio_bridge.launch.py
```

To use a different config file:

```bash
ros2 launch px4_vio_bridge vio_bridge.launch.py config_path:=/path/to/my_vio_bridge.yaml
```

### Whole pipeline in one terminal (`launch/vio_pipeline.launch.py`)

`make vio-pipeline` (from `/root` in the container) starts MicroXRCEAgent →
OAK-D Pro driver → OpenVINS → this bridge, with the same configs as
`make depthai` / `make openvins` / `make vio-bridge`. Each stage starts only
once the previous one works, as checked by the `wait_for_topics` helper
(same package):

| Before starting | Checks |
|---|---|
| camera | a message on `/fmu/out/vehicle_status_v1` (agent up, Pixhawk connected, domain OK) |
| OpenVINS | a message on each topic OpenVINS subscribes to (read from its config) |
| bridge | OpenVINS's odometry publisher exists (not a message: `odomimu` is only published once it has a subscriber) |

A failed check (after `stage_timeout`, default 60 s) or a crash of the agent,
OpenVINS or the bridge stops everything, with the reason in the log.
`ROS_DOMAIN_ID` is set to `ros_domain_id` (default 42, must match PX4's
`UXRCE_DDS_DOM_ID`) for every process, whatever the calling shell has.
OpenVINS runs in a pseudo-terminal so its `printf` output shows up live, and
it is also saved in the launch log directory. Other arguments: `agent_port`
(default 8888), `require_px4:=false` to skip the PX4 check and run without the
Pixhawk. Do not keep another MicroXRCEAgent running on the same port.

## Verifying it

```bash
ros2 topic hz /fmu/in/vehicle_visual_odometry      # should match odomimu's rate, > 50 Hz
ros2 topic echo --once /fmu/in/vehicle_visual_odometry
```

On PX4 (NSH), once `EKF2_EV_CTRL` is enabled, `listener vehicle_odometry` /
`listener estimator_status` should show the vision aid source active and
matching the physical motion of the vehicle. See [CLAUDE.md](../../../CLAUDE.md)
for the EKF2 parameters and the full validation sequence (bench test →
tethered flight → free flight).
