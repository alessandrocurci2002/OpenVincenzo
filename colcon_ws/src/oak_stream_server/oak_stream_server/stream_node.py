"""ROS 2 node that serves a ROS image topic as an MJPEG HTTP stream.

Bridges a `sensor_msgs/Image` topic (by default the OAK-D Pro's
`/oak/left/image_rect`) into a Flask app running in the same process, so it
can be viewed from a browser on the same (trusted) network without any ROS
client — e.g. from a laptop on the same Wi-Fi as the Raspberry Pi.

The subscriber callback and the Flask server run on separate threads and
only communicate through a lock-protected "latest JPEG frame" buffer: this
keeps a slow/blocked HTTP client from ever stalling the ROS callback, and
lets any number of browsers watch the same encoded frame at once instead of
each triggering its own image conversion.
"""

import logging
import shutil
import threading
import time

import cv2
import rclpy
from cv_bridge import CvBridge
from flask import Flask, Response
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image

INDEX_PAGE = """<!doctype html>
<title>{title}</title>
<body style="margin:0;background:#111">
  <img src="/stream" style="display:block;max-width:100%;margin:auto">
  <p style="color:#888;font:12px monospace;text-align:center">{url}<br><span id="disk">{disk}</span></p>
  <script>
    // Refreshed in place (not with a page reload, which would restart the stream):
    // a rosbag recording can eat the free space in minutes.
    setInterval(() => fetch("/disk").then(r => r.text()).then(t => document.getElementById("disk").textContent = t).catch(() => 0), 10000);
  </script>
</body>
"""


class _SkipDiskPoll(logging.Filter):
    # The page polls /disk every few seconds for as long as a browser is open;
    # without this each poll prints a werkzeug access-log line into the same
    # terminal as OpenVINS's output.
    def filter(self, record: logging.LogRecord) -> bool:
        return "GET /disk " not in record.getMessage()


class OakStreamServer(Node):

    def __init__(self):
        super().__init__("oak_stream_server")

        self.declare_parameter("input_topic", "/oak/left/image_rect")
        self.declare_parameter("http_host", "0.0.0.0")
        self.declare_parameter("http_port", 5000)
        self.declare_parameter("advertised_host", "")
        self.declare_parameter("fps_limit", 10.0)
        self.declare_parameter("jpeg_quality", 80)
        self.declare_parameter("disk_path", "/")

        self._input_topic = self.get_parameter("input_topic").value
        self._http_host = self.get_parameter("http_host").value
        self._http_port = self.get_parameter("http_port").value
        self._advertised_host = self.get_parameter("advertised_host").value
        self._min_period_s = 1.0 / float(self.get_parameter("fps_limit").value)
        self._jpeg_quality = int(self.get_parameter("jpeg_quality").value)
        self._disk_path = self.get_parameter("disk_path").value

        self._bridge = CvBridge()
        self._frame_lock = threading.Lock()
        self._latest_jpeg = None
        self._frame_version = 0
        self._last_encode_time = 0.0

        self.create_subscription(Image, self._input_topic, self._on_image, qos_profile_sensor_data)

        self._app = Flask(__name__)
        self._app.add_url_rule("/", "index", self._handle_index)
        self._app.add_url_rule("/stream", "stream", self._handle_stream)
        self._app.add_url_rule("/disk", "disk", self._disk_text)
        logging.getLogger("werkzeug").addFilter(_SkipDiskPoll())

        self.get_logger().info(
            f"Streaming '{self._input_topic}' at {self._reachable_url()} "
            f"(fps_limit={self.get_parameter('fps_limit').value}, jpeg_quality={self._jpeg_quality})"
        )

    def _reachable_url(self) -> str:
        # http_host is a bind address ("0.0.0.0" = every interface) and is
        # not itself something a second device can connect to; advertised_host
        # is the actual IP to browse to, purely for a friendlier startup log
        # and index page, and is not used for binding.
        if self._advertised_host:
            return f"http://{self._advertised_host}:{self._http_port}/"
        return f"http://<this host's IP, e.g. from 'hostname -I'>:{self._http_port}/"

    def _disk_text(self) -> str:
        # Same figure as `df` (free = space available to non-root users). Inside
        # the container "/" is an overlay on the host's root filesystem, so it
        # reports the host's disk, where the rosbags end up too.
        try:
            usage = shutil.disk_usage(self._disk_path)
        except OSError as exc:
            return f"Disk free: unavailable ({exc.strerror})"
        gib = 1024 ** 3
        return (
            f"Disk free: {usage.free / gib:.1f} GiB of {usage.total / gib:.1f} GiB "
            f"({100 * usage.free / usage.total:.0f}%)"
        )

    def _on_image(self, msg: Image) -> None:
        now = time.monotonic()
        if now - self._last_encode_time < self._min_period_s:
            return
        self._last_encode_time = now

        frame = self._bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        ok, encoded = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, self._jpeg_quality])
        if not ok:
            self.get_logger().warning("JPEG encoding failed, dropping frame")
            return

        with self._frame_lock:
            self._latest_jpeg = encoded.tobytes()
            self._frame_version += 1

    def _handle_index(self):
        return INDEX_PAGE.format(title=self._input_topic, url=self._reachable_url(), disk=self._disk_text())

    def _handle_stream(self):
        return Response(self._mjpeg_generator(), mimetype="multipart/x-mixed-replace; boundary=frame")

    def _mjpeg_generator(self):
        last_sent_version = -1
        while True:
            with self._frame_lock:
                jpeg, version = self._latest_jpeg, self._frame_version
            if jpeg is None or version == last_sent_version:
                time.sleep(self._min_period_s)
                continue
            last_sent_version = version
            yield b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpeg + b"\r\n"

    def run_flask(self) -> None:
        self._app.run(host=self._http_host, port=self._http_port, threaded=True, use_reloader=False)


def main(args=None):
    rclpy.init(args=args)
    node = OakStreamServer()
    flask_thread = threading.Thread(target=node.run_flask, daemon=True)
    flask_thread.start()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
