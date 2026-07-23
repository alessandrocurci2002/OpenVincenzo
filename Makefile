.PHONY: help depthai depthai-rectified openvins


#adding env variables

PROJECT_DIR := $(shell pwd)/depthai-ws
CAMERA_CONFIG := $(PROJECT_DIR)/src/depthai-ros/depthai_ros_driver/config/stereo.yaml
OPENVINS_CONFIG := /root/colcon_ws/src/open_vins/config/oakdpro_calib05/estimator_config.yaml

build-depthai:
	@echo "Building DepthAI ROS driver..."
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

build-depthai:
	@echo "Building DepthAI ROS driver..."
	cd depthai-ws && \
	rosdep install --from-paths src --ignore-src -r -y && \
	MAKEFLAGS="-j1 -l1" colcon build --symlink-install && \
	cd src && \
	source /root/depthai-ws/install/setup.bash


openvins:
	@echo "Launching OpenVINS..."
	cd colcon_ws/src && \
	ros2 run ov_msckf run_subscribe_msckf --ros-args -p config_path:=$(OPENVINS_CONFIG)


