# oak_stream_server

Serves a ROS 2 `sensor_msgs/Image` topic (by default the OAK-D Pro's
`/oak/left/image_rect`) as an MJPEG stream over plain HTTP, so it can be
viewed from a browser on the same network — no ROS client, no VPN, nothing
to install on the viewing device.

```
/oak/left/image_rect  --sensor_msgs/Image-->  oak_stream_server  --HTTP MJPEG-->  browser on the local network
                                  (this package, Flask app in the same process)
```

## Why

Useful to eyeball what the camera actually sees (framing, focus, exposure,
rectification) from a laptop, without opening `rviz2` or an X11 forward —
handy when the Raspberry Pi is headless and only reachable over Wi-Fi.

**Assumes the local network is trusted**: there is no authentication or
TLS. Do not expose `http_port` beyond your own LAN.

## Running it

```bash
ros2 launch oak_stream_server oak_stream.launch.py
```

Then, from any device on the same network as the Raspberry Pi:

```
http://<raspberry-pi-ip>:5000/
```

(`hostname -I` on the Raspberry Pi lists its current IPs, Wi-Fi included —
the container runs with `--net=host`, so the Flask server bound inside it is
directly reachable on the host's own IPs, no port publishing needed. Set
`advertised_host` in the config to have the node print this URL for you at
startup instead of having to look it up each time.)

To use a different config file:

```bash
ros2 launch oak_stream_server oak_stream.launch.py config_path:=/path/to/my_oak_stream.yaml
```

## Parameters (`config/oak_stream.yaml`)

| Parameter | Default | Meaning |
|---|---|---|
| `input_topic` | `/oak/left/image_rect` | `sensor_msgs/Image` topic to stream |
| `http_host` | `0.0.0.0` | bind address; `0.0.0.0` = every IP the host has, or set one specific interface IP to restrict it |
| `http_port` | `5000` | HTTP port |
| `advertised_host` | `""` | purely cosmetic: the IP to show in the startup log / index page as the URL to browse to (e.g. the Raspberry Pi's Wi-Fi IP). Does **not** affect binding — `http_host` does that. Empty prints a generic "run `hostname -I`" hint instead |
| `disk_path` | `/` | path whose filesystem's free space is shown under the stream (see below). `/` is the Raspberry Pi's root filesystem also from inside the container |
| `fps_limit` | `10.0` | frames actually encoded/served per second — keep this low, it trades directly against CPU on the Raspberry Pi 5 (no GPU), which OpenVINS also needs |
| `jpeg_quality` | `80` | `cv2.IMWRITE_JPEG_QUALITY` (0-100); lower = less CPU/bandwidth, blockier image |

## Free disk space

Under the image the page shows the free space left on the Raspberry Pi
(`Disk free: 17.2 GiB of 58.4 GiB (29%)`, same figure as `df`). It is updated
every 10 s by a small script fetching `/disk` (plain text), without reloading
the page, so the stream is not interrupted — useful while recording a rosbag.
Those polls are filtered out of the Flask access log to keep the terminal
readable. Note that the Raspberry Pi boots from an SD card, and the repo,
Docker's data and the rosbags all live on that single filesystem.

## How it works

A single ROS subscriber callback throttles to `fps_limit`, converts the
frame with `cv_bridge`, and JPEG-encodes it into a lock-protected "latest
frame" buffer. `rclpy.spin()` runs on one thread, the Flask dev server
(`threaded=True`, so it can hold several long-lived MJPEG connections at
once) on another; they only ever touch that shared buffer. Every browser
that opens `/stream` gets the same encoded frame — the image is converted
and compressed once regardless of how many viewers are watching, not once
per client.

## Dependencies

`cv_bridge` and OpenCV come from the same `rosdep install` step that
already installs them for OpenVINS (`ov_core`/`ov_init`/`ov_msckf` depend on
`cv_bridge` too). **Flask is installed system-wide via `apt`
(`python3-flask`) in the top-level `Dockerfile`**, not declared in this
package's `package.xml`: it has no dependable `rosdep` key, and a failing
key there would break `rosdep install` for the whole workspace, not just
this package.
