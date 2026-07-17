.PHONY: help depthai depthai-rectified openvins


#adding env variables

PROJECT_DIR := $(shell pwd)/depthai-ws
CAMERA_CONFIG := $(PROJECT_DIR)/src/depthai-ros/depthai_ros_driver/config/stereo.yaml

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@echo "  make depthai            Launch the DepthAI driver with rectified infra streams"
	@echo "  make depthai-rectified  Launch the DepthAI driver with rectified infra streams only"
	@echo "  make openvins           Launch OpenVINS with the example subscriber"

# Launch the DepthAI driver with rectified stereo images enabled
# Requires the ROS 2 environment to be sourced first.

depthai-rviz:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		rs_compat:=false \
		enable_infra1:=false \
		enable_infra2:=false \
		pointcloud.enable:=true \
		camera.i_enable_imu:=false \
		use_rviz:=true

depthai:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		use_rviz:=false \
		params_file:=$(CAMERA_CONFIG)

#       
# 		left.i_disable_node:=true \
# 		right.i_disable_node:=true \

depthai-rectified:
	@echo "Launching DepthAI driver with rectified infra streams only..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		rs_compat:=true \
		enable_infra1:=true \
		enable_infra2:=true \
		enable_color:=true \
		enable_depth:=true \
		pointcloud.enable:=true \
		camera.i_enable_imu:=true

depthai-rectified-rviz:
	@echo "Launching DepthAI driver with rectified infra streams only..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		rs_compat:=true \
		enable_infra1:=true \
		enable_infra2:=true \
		enable_color:=true \
		enable_depth:=true \
		pointcloud.enable:=true \
		camera.i_enable_imu:=true \
		use_rviz:=true

openvins:
	@echo "Launching OpenVINS..."
	source ~/colcon_ws/install/setup.bash
	
	ros2 run ov_msckf run_subscribe_msckf --ros-args -p config_path:=/root/colcon_ws/src/open_vins/config/oakdpro/estimator_config.yaml
