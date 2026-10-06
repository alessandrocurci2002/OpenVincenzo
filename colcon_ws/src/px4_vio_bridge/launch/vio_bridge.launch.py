import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

launch_args = [
    DeclareLaunchArgument(
        name="config_path",
        default_value=os.path.join(
            get_package_share_directory("px4_vio_bridge"), "config", "vio_bridge.yaml"
        ),
        description="path to the bridge's YAML parameter file",
    ),
]


def generate_launch_description():
    node = Node(
        package="px4_vio_bridge",
        executable="vio_to_px4_bridge",
        name="vio_to_px4_bridge",
        output="screen",
        parameters=[LaunchConfiguration("config_path")],
    )
    return LaunchDescription(launch_args + [node])
