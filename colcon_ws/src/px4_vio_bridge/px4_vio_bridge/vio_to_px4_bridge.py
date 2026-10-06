"""Bridge node: OpenVINS `odomimu` (nav_msgs/Odometry) -> PX4 `VehicleOdometry`.

Frame conversion applied on every message (see package README for the full
derivation):

  * position / orientation: OpenVINS publishes in its own "global" world
    frame (gravity-aligned, z-up, arbitrary heading fixed at init). PX4's
    POSE_FRAME_FRD is the same kind of frame (arbitrary heading, z-down), so
    only a fixed 180 deg rotation about x is needed.
  * linear/angular velocity: OpenVINS reports these already in the IMU's own
    body frame, matching PX4's VELOCITY_FRAME_BODY_FRD. Only a fixed
    IMU-to-drone-body rotation is needed (the `imu_to_body_rotation_deg`
    parameter), to account for the OpenVINS IMU (OAK-D Pro, ~camera-optical
    axes) not being mounted with its axes aligned to the drone's FRD body.
"""

import numpy as np
import rclpy
from nav_msgs.msg import Odometry
from px4_msgs.msg import VehicleOdometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy

from px4_vio_bridge import frame_transforms as ft


class VioToPx4Bridge(Node):

    def __init__(self):
        super().__init__("vio_to_px4_bridge")

        self.declare_parameter("input_topic", "/ov_msckf/odomimu")
        self.declare_parameter("output_topic", "/fmu/in/vehicle_visual_odometry")
        self.declare_parameter("input_qos_reliability", "reliable")
        self.declare_parameter("input_qos_depth", 10)
        self.declare_parameter("output_qos_depth", 5)
        self.declare_parameter("imu_to_body_rotation_deg", [90.0, 0.0, 90.0])

        input_topic = self.get_parameter("input_topic").value
        output_topic = self.get_parameter("output_topic").value
        roll, pitch, yaw = self.get_parameter("imu_to_body_rotation_deg").value

        self._r_body_from_ov = ft.rotation_matrix_from_euler_deg(roll, pitch, yaw)
        self._q_body_from_ov_conj = ft.quat_conjugate(ft.quat_from_rotation_matrix(self._r_body_from_ov))

        input_qos = QoSProfile(
            reliability=self._reliability_from_param(self.get_parameter("input_qos_reliability").value),
            durability=DurabilityPolicy.VOLATILE,
            history=HistoryPolicy.KEEP_LAST,
            depth=self.get_parameter("input_qos_depth").value,
        )
        # PX4's uXRCE-DDS client subscribes BEST_EFFORT: this is not a tunable
        # knob, a RELIABLE publisher here means silently-dropped messages.
        output_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
            history=HistoryPolicy.KEEP_LAST,
            depth=self.get_parameter("output_qos_depth").value,
        )

        self._pub = self.create_publisher(VehicleOdometry, output_topic, output_qos)
        self._sub = self.create_subscription(Odometry, input_topic, self._on_odom, input_qos)

        self.get_logger().info(
            f"Bridging '{input_topic}' (nav_msgs/Odometry) -> '{output_topic}' (px4_msgs/VehicleOdometry), "
            f"imu_to_body_rotation_deg=[{roll}, {pitch}, {yaw}]"
        )

    @staticmethod
    def _reliability_from_param(value: str) -> ReliabilityPolicy:
        value = value.lower()
        if value == "best_effort":
            return ReliabilityPolicy.BEST_EFFORT
        if value == "reliable":
            return ReliabilityPolicy.RELIABLE
        raise ValueError(f"input_qos_reliability must be 'reliable' or 'best_effort', got '{value}'")

    def _on_odom(self, msg: Odometry) -> None:
        p_ov = np.array(
            [msg.pose.pose.position.x, msg.pose.pose.position.y, msg.pose.pose.position.z]
        )
        # ROS quaternion order is (x,y,z,w); PX4/Hamilton order is (w,x,y,z).
        q_ov = np.array(
            [
                msg.pose.pose.orientation.w,
                msg.pose.pose.orientation.x,
                msg.pose.pose.orientation.y,
                msg.pose.pose.orientation.z,
            ]
        )
        v_ov = np.array(
            [msg.twist.twist.linear.x, msg.twist.twist.linear.y, msg.twist.twist.linear.z]
        )
        w_ov = np.array(
            [msg.twist.twist.angular.x, msg.twist.twist.angular.y, msg.twist.twist.angular.z]
        )
        pose_cov = np.array(msg.pose.covariance).reshape(6, 6)
        twist_cov = np.array(msg.twist.covariance).reshape(6, 6)

        p_frd = ft.WORLD_ROTATION_MATRIX @ p_ov
        q_frd = ft.quat_normalize(
            ft.quat_multiply(ft.quat_multiply(ft.WORLD_ROTATION_QUAT, q_ov), self._q_body_from_ov_conj)
        )
        v_body = self._r_body_from_ov @ v_ov
        w_body = self._r_body_from_ov @ w_ov

        position_variance = np.diag(
            ft.rotate_covariance(pose_cov[0:3, 0:3], ft.WORLD_ROTATION_MATRIX)
        )
        # OpenVINS's attitude-error covariance frame is not documented; treating
        # it as IMU-body (like the MSCKF error-state) is a reasonable default,
        # not empirically verified against the drone's actual behaviour yet.
        orientation_variance = np.diag(
            ft.rotate_covariance(pose_cov[3:6, 3:6], self._r_body_from_ov)
        )
        velocity_variance = np.diag(
            ft.rotate_covariance(twist_cov[0:3, 0:3], self._r_body_from_ov)
        )

        out = VehicleOdometry()
        # Use the VIO sample time carried in the message header, never the
        # bridge's own wall clock: get_clock().now() would fold this node's
        # scheduling jitter into what EKF2 treats as a physical sensor delay.
        stamp_us = msg.header.stamp.sec * 1_000_000 + msg.header.stamp.nanosec // 1000
        out.timestamp = stamp_us
        out.timestamp_sample = stamp_us

        out.pose_frame = VehicleOdometry.POSE_FRAME_FRD
        out.position = [float(v) for v in p_frd]
        out.q = [float(v) for v in q_frd]

        out.velocity_frame = VehicleOdometry.VELOCITY_FRAME_BODY_FRD
        out.velocity = [float(v) for v in v_body]
        out.angular_velocity = [float(v) for v in w_body]

        out.position_variance = [float(v) for v in position_variance]
        out.orientation_variance = [float(v) for v in orientation_variance]
        out.velocity_variance = [float(v) for v in velocity_variance]

        # OpenVINS gives no re-initialisation signal on this topic; bumping
        # this on filter reset is not implemented yet (see package README).
        out.reset_counter = 0
        out.quality = 0

        self._pub.publish(out)


def main(args=None):
    rclpy.init(args=args)
    node = VioToPx4Bridge()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
