.PHONY: help depthai depthai-rectified openvins


#adding env variables

PROJECT_DIR := $(shell pwd)/depthai-ws
CAMERA_CONFIG := $(PROJECT_DIR)/src/depthai-ros/depthai_ros_driver/config/stereo.yaml
# OPENVINS_CONFIG := /root/colcon_ws/src/open_vins/config/oakdpro_calib05_newImucalib/estimator_config.yaml
OPENVINS_CONFIG := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval/rosbags/test_3/oakdpro_test_3_v1/estimator_config.yaml
ROSBAG_PLAY_DIR := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval/rosbags/test_3/prova_tagslam3

OPENVINS_SAVE_DIR := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval/rosbags/test_3/oakdpro_test_3_v1
OPENVINS_FILEPATH_EST := $(OPENVINS_SAVE_DIR)/ov_estimate.txt
OPENVINS_FILEPATH_STD := $(OPENVINS_SAVE_DIR)/ov_estimate_std.txt
OPENVINS_FILEPATH_GT := $(OPENVINS_SAVE_DIR)/ov_groundtruth.txt

build-depthai:
	@echo "Building DepthAI ROS driver..."
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@echo "  make depthai            Launch the DepthAI driver with rectified infra streams"
	@echo "  make depthai-rectified  Launch the DepthAI driver with rectified infra streams only"
	@echo "  make openvins           Launch OpenVINS with the example subscriber"
	@echo "  make rviz-left-image    Launch rviz2 showing /oak/left/image_rect"
	@echo "  make rviz-trackhist     Launch rviz2 showing /trackhist and /pathimu (fixed frame: global)"

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

openvins_saveall: 
	@echo "Launching OpenVINS and saving files in $(OPENVINS_FILEPATH_EST) ..."
	cd colcon_ws/src && \
	ros2 run ov_msckf run_subscribe_msckf --ros-args \
		-p config_path:=$(OPENVINS_CONFIG) \
		-p save_total_state:=true \
		-p filepath_est:=$(OPENVINS_FILEPATH_EST) \
		-p filepath_std:=$(OPENVINS_FILEPATH_STD) \
		-p filepath_gt:=$(OPENVINS_FILEPATH_GT)


BAG_NAME ?= subset
rosrecord:
	@echo "Recording ROS topics..."
	ros2 bag record -o $(BAG_NAME) /oak/imu/data /oak/left/image_rect /oak/right/image_rect
	@echo "Recording complete. Bag file saved in the current directory under \"$(BAG_NAME)\"."

# run make rosrecord BAG_NAME=my_bag to specify the folder name

rosbag-postprocessing:
	@echo "Post-processing ROS bag..."
	@echo "Converting bag"
	rosbags-convert --src $(BAG_NAME) --dst $(BAG_NAME).bag
	@echo "moving the bag"
	mv $(BAG_NAME).bag depthai-ws/


rosbag-play:
	@echo "playing the rosbag $(ROSBAG_PLAY_DIR)"
	ros2 bag play $(ROSBAG_PLAY_DIR)
	@echo "playing finished"

RVIZ_CONFIG_LEFT_IMAGE := $(shell pwd)/colcon_ws/src/open_vins/rviz/left_image.rviz
RVIZ_CONFIG_TRACKHIST := $(shell pwd)/rviz/trackhist_pathimu.rviz

rviz-left-image:
	@echo "Launching rviz2 with /oak/left/image_rect..."
	ros2 run rviz2 rviz2 -d $(RVIZ_CONFIG_LEFT_IMAGE)

rviz-openvins:
	@echo "Launching rviz2 with /trackhist and /pathimu (fixed frame: global)..."
	ros2 run rviz2 rviz2 -d $(RVIZ_CONFIG_TRACKHIST)

