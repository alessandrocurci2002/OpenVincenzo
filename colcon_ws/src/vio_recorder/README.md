# vio_recorder

Records a configurable set of topics to a rosbag2 (sqlite3): VIO output,
what the bridge sends to PX4, PX4's vehicle state and the OAK-D Pro images.
The topics are chosen in [`config/recorder.yaml`](config/recorder.yaml).

```bash
make record                                   # inside the container, from /root
# or
ros2 launch vio_recorder recorder.launch.py config_path:=/path/to/my_recorder.yaml
```

Stop with Ctrl+C, or set `max_duration_s`. Each run creates
`<output_dir>/<bag_prefix>_<YYYYmmdd_HHMMSS>/` with the bag and a copy of the
config that produced it (`recorder_config.yaml`). By default `output_dir` is
`recordings/` in this package, which is mounted from the host and git-ignored.
The folder name uses the container's clock, which is UTC.

## Choosing the topics

Every entry of `topics:` has a `name` and an `enabled` flag: set
`enabled: false` to skip a topic without deleting it. Optional fields:

| Field | Default | Meaning |
|---|---|---|
| `type` | taken from the publisher | message type, e.g. `px4_msgs/msg/VehicleAttitude` |
| `qos` | `default_qos` (`auto`) | `auto`, `reliable` or `best_effort` |
| `depth` | `default_depth` (10) | subscription queue depth |

A topic is subscribed once a publisher is discovered, with its type and QoS
(`auto` = reliable only if every publisher is reliable, as `ros2 bag record`
does). If no publisher appears within `discovery_timeout_s`, topics with a
`type` are subscribed anyway, best effort; topics without one keep waiting.
Messages are written serialized, as received, so images are never decoded.

## Disk space

The two rectified 640x400 images at 30 fps are about 0.9 GB per minute.
Recording stops by itself when free space drops below `min_free_space_mb`
(default 1000 MB). Every `status_period_s` the node prints the rate, message
count and size of each topic and the free space left.

## Domain

The launch file sets `ROS_DOMAIN_ID` from its `ros_domain_id` argument
(default 42, the pipeline's), so a `docker exec` shell on domain 0 still sees
the topics.

## Container

The package is mounted and built like `px4_vio_bridge` (`dockerRun.sh`,
`entrypoint.sh`). A container created before it was added does not mount it:
recreate the container with `dockerRun.sh`.
