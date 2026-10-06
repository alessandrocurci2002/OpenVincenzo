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
            get_package_share_directory("oak_stream_server"), "config", "oak_stream.yaml"
        ),
        description="path to the stream server's YAML parameter file",
    ),
]


def generate_launch_description():
    node = Node(
        package="oak_stream_server",
        executable="stream_node",
        name="oak_stream_server",
        output="screen",
        parameters=[LaunchConfiguration("config_path")],
    )
    return LaunchDescription(launch_args + [node])
