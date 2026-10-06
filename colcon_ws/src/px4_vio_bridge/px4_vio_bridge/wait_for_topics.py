"""Block until ROS 2 topics are live, then exit.

Used by launch/vio_pipeline.launch.py to start a pipeline stage only once the
previous one actually works: a spawned process is not the same as a topic
that carries data.

    wait_for_topics [--timeout SEC] [--publisher-only] TOPIC [TOPIC ...]

By default it waits for the first message on every topic. With
--publisher-only it only waits for a publisher to show up in the ROS graph:
needed for topics whose publisher stays silent until someone subscribes
(OpenVINS publishes odomimu only if it already has a subscriber, so waiting
for a message there would deadlock).

Exit code: 0 when every topic is ready, 1 on timeout or error.
"""

import argparse
import sys
import time

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from rclpy.utilities import remove_ros_args
from rosidl_runtime_py.utilities import get_message

# BEST_EFFORT + VOLATILE is compatible with any publisher (RELIABLE or
# BEST_EFFORT, any durability): the same profile works for the camera topics
# and for PX4's /fmu/out/* topics.
_MATCH_ANY_PUBLISHER_QOS = QoSProfile(
    reliability=ReliabilityPolicy.BEST_EFFORT,
    durability=DurabilityPolicy.VOLATILE,
    history=HistoryPolicy.KEEP_LAST,
    depth=1,
)


def main(args=None):
    parser = argparse.ArgumentParser(description="Wait until ROS 2 topics are live.")
    parser.add_argument("topics", nargs="+", help="fully qualified topic names")
    parser.add_argument("--timeout", type=float, default=30.0, help="seconds before giving up")
    parser.add_argument(
        "--publisher-only",
        action="store_true",
        help="only wait for a publisher to exist, not for a message",
    )
    opts = parser.parse_args(remove_ros_args(sys.argv if args is None else args)[1:])

    rclpy.init(args=args)
    node = Node("wait_for_topics")
    log = node.get_logger()
    start = time.monotonic()
    pending = set(opts.topics)
    subscriptions = {}

    def mark_ready(topic):
        if topic in pending:
            pending.discard(topic)
            log.info(f"{topic}: ready after {time.monotonic() - start:.1f} s")

    what = "a publisher" if opts.publisher_only else "the first message"
    log.info(f"waiting up to {opts.timeout:.0f} s for {what} on: {' '.join(opts.topics)}")
    try:
        while pending and time.monotonic() - start < opts.timeout:
            if opts.publisher_only:
                for topic in list(pending):
                    if node.count_publishers(topic) > 0:
                        mark_ready(topic)
            else:
                # A subscription needs the message type, which is only known
                # once a publisher has announced the topic in the graph.
                types = dict(node.get_topic_names_and_types())
                for topic in pending - subscriptions.keys():
                    if topic not in types:
                        continue
                    try:
                        msg_type = get_message(types[topic][0])
                    except (AttributeError, ModuleNotFoundError, ValueError) as exc:
                        log.error(f"{topic}: cannot import {types[topic][0]} ({exc}), is its workspace sourced?")
                        return 1
                    # raw=True: no need to deserialize (e.g. full images) just to know one arrived.
                    subscriptions[topic] = node.create_subscription(
                        msg_type, topic, lambda _msg, t=topic: mark_ready(t), _MATCH_ANY_PUBLISHER_QOS, raw=True
                    )
            rclpy.spin_once(node, timeout_sec=0.1)
        if pending:
            log.error(f"timeout after {opts.timeout:.0f} s, still waiting for: {' '.join(sorted(pending))}")
            return 1
        return 0
    except (KeyboardInterrupt, ExternalShutdownException):
        return 1
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    sys.exit(main())
