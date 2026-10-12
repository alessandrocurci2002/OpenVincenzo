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

The SD card writes the bag slower than the images arrive (~10 vs ~15 MB/s)
and stalls for seconds at a time. `max_cache_size_mb` (default 2000) keeps the
backlog in RAM, up to twice that value, for a few minutes of recording; if it
fills, rosbag2 drops messages and prints `Cache buffers lost messages` at the
end. After Ctrl+C the node first writes the cache to disk, which can take
minutes: wait for `bag closed`, the launch file does not kill it for 10
minutes. The launch file also disables the node's log file in `~/.ros/log`
(`--disable-external-lib-logs`): writing it during a stall blocked the node
and left 8–23 s holes in every topic. The real fix is a faster disk (USB 3 SSD).

## Domain

The launch file sets `ROS_DOMAIN_ID` from its `ros_domain_id` argument
(default 42, the pipeline's), so a `docker exec` shell on domain 0 still sees
the topics.

## Container

The package is mounted and built like `px4_vio_bridge` (`dockerRun.sh`,
`entrypoint.sh`). A container created before it was added does not mount it:
recreate the container with `dockerRun.sh`.
