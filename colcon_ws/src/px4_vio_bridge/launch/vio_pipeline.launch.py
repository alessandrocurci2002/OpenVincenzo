"""Full VIO -> PX4 pipeline, started one stage at a time:

  1. MicroXRCEAgent    uXRCE-DDS agent, link to PX4 over Ethernet
  2. OAK-D Pro driver  same launch and parameters as `make depthai`
  3. OpenVINS          same node and config as `make openvins`
  4. px4_vio_bridge    same node and config as `make vio-bridge`

A stage starts only once the previous one is verifiably working, not just
spawned (checked with the wait_for_topics helper):

  1 -> 2  PX4 data arrives on /fmu/out/vehicle_status_v1: agent up, Pixhawk
          connected, ROS_DOMAIN_ID equal to UXRCE_DDS_DOM_ID. Skipped with
          require_px4:=false (VIO chain without the Pixhawk).
  2 -> 3  first message on every topic OpenVINS subscribes to, read from the
          OpenVINS config itself, so the check follows whichever config is used.
  3 -> 4  OpenVINS has created the publisher of the bridge's input_topic. Only
          the publisher is checked, not messages: OpenVINS publishes odomimu
          only once it has a subscriber, i.e. only after the bridge is up.

A failed check, or a core process (agent, OpenVINS, bridge) exiting on its
own, stops the whole launch with the reason in the log.

Usually started with `make vio-pipeline`, which passes the same config paths
as the single-stage make targets.
"""

import os

import yaml
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    ExecuteProcess,
    GroupAction,
    IncludeLaunchDescription,
    LogInfo,
    OpaqueFunction,
    RegisterEventHandler,
    SetEnvironmentVariable,
    Shutdown,
)
from launch.event_handlers import OnProcessExit, OnProcessStart
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

# Versioned message (VehicleStatus v1), hence the _v1 suffix.
PX4_CHECK_TOPIC = "/fmu/out/vehicle_status_v1"

launch_args = [
    DeclareLaunchArgument(
        "camera_params_file",
        description="depthai_ros_driver_v3 parameter file (Makefile: CAMERA_CONFIG)",
    ),
    DeclareLaunchArgument(
        "openvins_config",
        description="OpenVINS estimator_config.yaml (Makefile: OPENVINS_CONFIG)",
    ),
    DeclareLaunchArgument(
        "bridge_config",
        default_value=os.path.join(
            get_package_share_directory("px4_vio_bridge"), "config", "vio_bridge.yaml"
        ),
        description="px4_vio_bridge parameter file (Makefile: VIO_BRIDGE_CONFIG)",
    ),
    DeclareLaunchArgument(
        "agent_port", default_value="8888", description="must match PX4's UXRCE_DDS_PRT"
    ),
    DeclareLaunchArgument(
        "ros_domain_id",
        default_value="42",
        description="must match PX4's UXRCE_DDS_DOM_ID; applied to every process of this launch",
    ),
    DeclareLaunchArgument(
        "require_px4",
        default_value="true",
        description="wait for PX4 data before starting the camera; false to run without the Pixhawk",
    ),
    DeclareLaunchArgument(
        "stage_timeout",
        default_value="60",
        description="seconds each stage may take to come up before the launch gives up",
    ),
]


def _load_opencv_yaml(path):
    # OpenVINS configs are OpenCV-style YAML: PyYAML rejects the "%YAML:1.0" header.
    with open(path) as f:
        return yaml.safe_load("".join(line for line in f if not line.startswith("%")))


def _openvins_input_topics(config_path):
    """The topics run_subscribe_msckf subscribes to, resolved like ROS2Visualizer does."""
    config_dir = os.path.dirname(config_path)
    estimator = _load_opencv_yaml(config_path)
    imu = _load_opencv_yaml(os.path.join(config_dir, estimator["relative_config_imu"]))
    imucam = _load_opencv_yaml(os.path.join(config_dir, estimator["relative_config_imucam"]))
    cameras = [imucam[f"cam{i}"]["rostopic"] for i in range(estimator["max_cameras"])]
    return [imu["imu0"]["rostopic"]] + cameras


def _bridge_input_topic(config_path):
    with open(config_path) as f:
        for node_params in yaml.safe_load(f).values():
            topic = node_params.get("ros__parameters", {}).get("input_topic")
            if topic:
                return topic
    return "/ov_msckf/odomimu"  # vio_to_px4_bridge's own default


def _stop_pipeline(reason):
    return [LogInfo(msg=f"[vio_pipeline] {reason}: stopping the pipeline"), Shutdown(reason=reason)]


def _stop_if_exits(what):
    """on_exit of a core process: a crash stops everything, a Ctrl+C stays quiet."""

    def handler(event, context):
        if context.is_shutdown:
            return None
        return _stop_pipeline(f"{what} exited with code {event.returncode}")

    return handler


def _waiter(name, topics, timeout, publisher_only=False):
    return Node(
        package="px4_vio_bridge",
        executable="wait_for_topics",
        name=name,
        arguments=["--timeout", timeout] + (["--publisher-only"] if publisher_only else []) + topics,
        output="screen",
    )


def _after(waiter, next_actions, failure):
    """Start next_actions if waiter succeeds, stop the pipeline if it fails."""

    def handler(event, context):
        if context.is_shutdown:
            return None
        if event.returncode == 0:
            return next_actions
        return _stop_pipeline(failure)

    return RegisterEventHandler(OnProcessExit(target_action=waiter, on_exit=handler))


def _launch_setup(context):
    timeout = LaunchConfiguration("stage_timeout").perform(context)
    openvins_config = LaunchConfiguration("openvins_config").perform(context)
    bridge_config = LaunchConfiguration("bridge_config").perform(context)
    require_px4 = LaunchConfiguration("require_px4").perform(context).lower() == "true"

    agent = ExecuteProcess(
        name="micro_xrce_agent",
        cmd=["MicroXRCEAgent", "udp4", "-p", LaunchConfiguration("agent_port")],
        output="screen",
        on_exit=_stop_if_exits("MicroXRCEAgent"),
    )

    # Scoped group: the driver's own launch arguments (name, namespace,
    # params_file, ...) must not leak into this launch.
    camera = GroupAction(
        [
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(
                    os.path.join(
                        get_package_share_directory("depthai_ros_driver_v3"),
                        "launch",
                        "driver.launch.py",
                    )
                ),
                launch_arguments={
                    "use_rviz": "false",
                    "params_file": LaunchConfiguration("camera_params_file"),
                }.items(),
            )
        ]
    )

    openvins = Node(
        package="ov_msckf",
        executable="run_subscribe_msckf",
        parameters=[{"config_path": openvins_config}],
        # OpenVINS prints with printf: on a pipe its stdout is block-buffered
        # and the messages show up late and in chunks. A pseudo-terminal keeps
        # them live (and coloured) as in `make openvins`; "both" also keeps a
        # copy in the launch log directory.
        emulate_tty=True,
        output="both",
        on_exit=_stop_if_exits("OpenVINS"),
    )

    bridge = Node(
        package="px4_vio_bridge",
        executable="vio_to_px4_bridge",
        name="vio_to_px4_bridge",
        output="screen",
        parameters=[bridge_config],
        on_exit=_stop_if_exits("px4_vio_bridge"),
    )

    wait_camera = _waiter("wait_for_camera", _openvins_input_topics(openvins_config), timeout)
    wait_openvins = _waiter(
        "wait_for_openvins", [_bridge_input_topic(bridge_config)], timeout, publisher_only=True
    )

    actions = [
        agent,
        _after(wait_camera, [openvins, wait_openvins], "the topics OpenVINS needs are not arriving"),
        _after(wait_openvins, [bridge], "OpenVINS did not come up"),
    ]
    if require_px4:
        wait_px4 = _waiter("wait_for_px4", [PX4_CHECK_TOPIC], timeout)
        actions += [
            RegisterEventHandler(OnProcessStart(target_action=agent, on_start=[wait_px4])),
            _after(
                wait_px4,
                [camera, wait_camera],
                f"no PX4 data on {PX4_CHECK_TOPIC} (Pixhawk connected? UXRCE_DDS_DOM_ID == ros_domain_id?)",
            ),
        ]
    else:
        actions.append(RegisterEventHandler(OnProcessStart(target_action=agent, on_start=[camera, wait_camera])))
    return actions


def generate_launch_description():
    return LaunchDescription(
        launch_args
        + [
            # Inherited by every ROS process below: shells opened with
            # `docker exec` start on domain 0, where PX4's topics are invisible.
            SetEnvironmentVariable("ROS_DOMAIN_ID", LaunchConfiguration("ros_domain_id")),
            OpaqueFunction(function=_launch_setup),
        ]
    )
