import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, SetEnvironmentVariable
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

launch_args = [
    DeclareLaunchArgument(
        name="config_path",
        default_value=os.path.join(get_package_share_directory("vio_recorder"), "config", "recorder.yaml"),
        description="recorder YAML: topics to record, output directory, limits",
    ),
    DeclareLaunchArgument(
        name="ros_domain_id",
        default_value="42",
        description="must match the domain of the pipeline (and PX4's UXRCE_DDS_DOM_ID)",
    ),
]


def generate_launch_description():
    node = Node(
        package="vio_recorder",
        executable="vio_recorder",
        name="vio_recorder",
        output="screen",
        parameters=[{"config_path": LaunchConfiguration("config_path")}],
    )
    # Shells opened with `docker exec` start on domain 0, where the pipeline's
    # topics are invisible: same fix as vio_pipeline.launch.py.
    return LaunchDescription(
        launch_args + [SetEnvironmentVariable("ROS_DOMAIN_ID", LaunchConfiguration("ros_domain_id")), node]
    )
