"""Record a configurable set of topics to a rosbag2 (sqlite3).

The topics, their QoS and the output location are chosen in a YAML file
(config/recorder.yaml), passed to the node as the `config_path` parameter.
Messages are stored exactly as received (serialized CDR): the node never
deserializes them, so a camera image costs one copy, not a conversion.

A topic is subscribed only once one of its publishers has been discovered,
so the message type and the QoS can be taken from the publisher itself, as
`ros2 bag record` does. Topics whose publisher never appears are subscribed
anyway after `discovery_timeout_s`, if their type is given in the config.
"""

import os
import shutil
import time
from datetime import datetime

import rclpy
import rosbag2_py
import yaml
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from rosidl_runtime_py.utilities import get_message

MB = 1024 * 1024


class _StopRecording(Exception):
    """Raised from a timer callback to leave rclpy.spin() cleanly."""


class _Topic:
    def __init__(self, entry, default_qos, default_depth):
        self.name = entry["name"]
        self.type = entry.get("type") or None
        self.qos = str(entry.get("qos", default_qos)).lower()
        self.depth = int(entry.get("depth", default_depth))
        self.count = 0
        self.count_last = 0
        self.bytes = 0
        self.subscribed = False
        if self.qos not in ("auto", "reliable", "best_effort"):
            raise ValueError(f"{self.name}: qos must be auto, reliable or best_effort, got '{self.qos}'")


class TopicRecorder(Node):

    def __init__(self):
        super().__init__("vio_recorder")
        self.declare_parameter("config_path", "")
        config_path = self.get_parameter("config_path").value
        if not config_path:
            raise RuntimeError("parameter config_path is not set")
        with open(config_path) as f:
            cfg = yaml.safe_load(f)

        self._max_duration = float(cfg.get("max_duration_s", 0))
        self._discovery_timeout = float(cfg.get("discovery_timeout_s", 10))
        self._min_free_mb = float(cfg.get("min_free_space_mb", 1000))
        default_qos = cfg.get("default_qos", "auto")
        default_depth = cfg.get("default_depth", 10)

        self._topics = []
        seen = set()
        for entry in cfg.get("topics", []):
            if not entry.get("enabled", True):
                continue
            if entry["name"] in seen:
                self.get_logger().warning(f"{entry['name']} listed twice, keeping the first entry")
                continue
            seen.add(entry["name"])
            self._topics.append(_Topic(entry, default_qos, default_depth))
        if not self._topics:
            raise RuntimeError(f"no enabled topic in {config_path}")

        output_dir = os.path.expanduser(cfg.get("output_dir", "~/recordings"))
        os.makedirs(output_dir, exist_ok=True)
        self._output_dir = output_dir
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._bag_path = os.path.join(output_dir, f"{cfg.get('bag_prefix', 'rec')}_{stamp}")

        self._writer = rosbag2_py.SequentialWriter()
        self._writer.open(
            rosbag2_py.StorageOptions(
                uri=self._bag_path,
                storage_id="sqlite3",
                max_bagfile_size=int(float(cfg.get("max_bagfile_size_mb", 0)) * MB),
                # Non-zero cache: rosbag2 writes to disk from its own thread,
                # so the subscription callbacks never wait for sqlite.
                max_cache_size=int(float(cfg.get("max_cache_size_mb", 100)) * MB),
            ),
            rosbag2_py.ConverterOptions("cdr", "cdr"),
        )
        # Keep the exact configuration next to the data it produced.
        shutil.copyfile(config_path, os.path.join(self._bag_path, "recorder_config.yaml"))

        self._t_start = time.monotonic()
        self._stop_reason = None
        self._status_period = float(cfg.get("status_period_s", 5))
        self.create_timer(0.5, self._discover)
        self.create_timer(self._status_period, self._status)

        self.get_logger().info(
            f"recording to {self._bag_path}: "
            + ", ".join(t.name for t in self._topics)
            + (f" (stop after {self._max_duration:.0f} s)" if self._max_duration > 0 else " (stop with Ctrl+C)")
        )

    # ------------------------------------------------------------------ subscriptions

    def _discover(self):
        elapsed = time.monotonic() - self._t_start
        if self._max_duration > 0 and elapsed >= self._max_duration:
            self._stop_reason = f"max_duration_s ({self._max_duration:.0f} s) reached"
            raise _StopRecording()

        for topic in self._topics:
            if topic.subscribed:
                continue
            infos = self.get_publishers_info_by_topic(topic.name)
            if infos:
                found_type = infos[0].topic_type
                if topic.type and topic.type != found_type:
                    self.get_logger().warning(
                        f"{topic.name}: config says {topic.type}, publisher says {found_type}; using the publisher's"
                    )
                reliable = all(i.qos_profile.reliability == ReliabilityPolicy.RELIABLE for i in infos)
                self._subscribe(topic, found_type, reliable)
            elif topic.type and elapsed > self._discovery_timeout:
                self.get_logger().warning(
                    f"{topic.name}: no publisher after {self._discovery_timeout:.0f} s, "
                    "subscribing anyway (best effort) with the type from the config"
                )
                self._subscribe(topic, topic.type, reliable=False)

    def _subscribe(self, topic, type_name, reliable):
        try:
            msg_class = get_message(type_name)
        except (AttributeError, ModuleNotFoundError, ValueError) as e:
            self.get_logger().error(f"{topic.name}: cannot load type {type_name} ({e}); is its workspace sourced?")
            topic.subscribed = True  # do not retry every 0.5 s
            return

        if topic.qos == "reliable":
            reliable = True
        elif topic.qos == "best_effort":
            reliable = False
        qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE if reliable else ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
            history=HistoryPolicy.KEEP_LAST,
            depth=topic.depth,
        )
        self._writer.create_topic(rosbag2_py.TopicMetadata(topic.name, type_name, "cdr", ""))

        def callback(data, topic=topic):
            # Same timestamp `ros2 bag record` stores: reception time on this node.
            self._writer.write(topic.name, data, self.get_clock().now().nanoseconds)
            topic.count += 1
            topic.bytes += len(data)

        self.create_subscription(msg_class, topic.name, callback, qos, raw=True)
        topic.subscribed = True
        self.get_logger().info(
            f"subscribed {topic.name} [{type_name}], {'reliable' if reliable else 'best effort'}, depth {topic.depth}"
        )

    # ------------------------------------------------------------------ status

    def _status(self):
        lines = []
        for t in self._topics:
            rate = (t.count - t.count_last) / self._status_period
            t.count_last = t.count
            state = f"{rate:6.1f} Hz  {t.count:7d} msg  {t.bytes / MB:8.1f} MB" if t.subscribed else "  waiting for a publisher"
            lines.append(f"  {t.name:45s} {state}")
        free_mb = shutil.disk_usage(self._output_dir).free / MB
        elapsed = time.monotonic() - self._t_start
        self.get_logger().info(f"{elapsed:6.0f} s, {free_mb:.0f} MB free on disk\n" + "\n".join(lines))
        if free_mb < self._min_free_mb:
            self._stop_reason = f"free disk space below min_free_space_mb ({free_mb:.0f} < {self._min_free_mb:.0f} MB)"
            raise _StopRecording()

    # ------------------------------------------------------------------ shutdown

    def close(self):
        self._writer.close()
        total = sum(t.bytes for t in self._topics) / MB
        summary = "\n".join(f"  {t.name:45s} {t.count:7d} msg" for t in self._topics)
        self.get_logger().info(
            f"bag closed: {self._bag_path} ({total:.1f} MB, stopped because: {self._stop_reason or 'Ctrl+C'})\n{summary}"
        )


def main(args=None):
    rclpy.init(args=args)
    node = TopicRecorder()
    try:
        rclpy.spin(node)
    except (_StopRecording, KeyboardInterrupt):
        pass
    finally:
        node.close()
        node.destroy_node()
        # The SIGINT handler may already have shut the context down.
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
