.PHONY: help depthai depthai-rectified openvins vio-bridge vio-pipeline oak-stream tagslam-detect tagslam-run tagslam-gt


#adding env variables

PROJECT_DIR := $(shell pwd)/depthai-ws
CAMERA_CONFIG := $(PROJECT_DIR)/src/depthai-ros/depthai_ros_driver/config/stereo.yaml
OPENVINS_CONFIG := /root/colcon_ws/src/open_vins/config/oakdpro_calib05_newImucalib/estimator_config.yaml
# OPENVINS_CONFIG := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval/rosbags/test_3/oakdpro_test_3_v1/estimator_config.yaml
ROSBAG_PLAY_DIR := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval/rosbags/test_3/prova_tagslam3
VIO_BRIDGE_CONFIG := /root/colcon_ws/src/px4_vio_bridge/config/vio_bridge.yaml
OAK_STREAM_CONFIG := /root/colcon_ws/src/oak_stream_server/config/oak_stream.yaml

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
	@echo "  make vio-bridge         Launch the OpenVINS -> PX4 VehicleOdometry bridge"
	@echo "  make vio-pipeline       Launch agent + DepthAI + OpenVINS + VIO bridge, one stage at a time"
	@echo "  make oak-stream         Launch the /oak/left/image_rect -> MJPEG HTTP stream server"
	@echo "  make rviz-left-image    Launch rviz2 showing /oak/left/image_rect"
	@echo "  make rviz-trackhist     Launch rviz2 showing /trackhist and /pathimu (fixed frame: global)"
	@echo ""
	@echo "TagSLAM ground truth (only in the Jazzy container: ./dockerRun_tagslam.sh):"
	@echo "  make tagslam-detect     Detect the AprilTags in the rosbag2 (TAGSLAM_BAG)"
	@echo "  make tagslam-run        Run TagSLAM on the detected tags"
	@echo "  make tagslam-gt         Write the trajectory to OpenVINS_eval/truths/<TEST>.txt"

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


vio-bridge:
	@echo "Launching PX4 VIO bridge..."
	ros2 launch px4_vio_bridge vio_bridge.launch.py config_path:=$(VIO_BRIDGE_CONFIG)


# MicroXRCEAgent -> DepthAI -> OpenVINS -> VIO bridge in one terminal, each stage
# started only once the previous one works. Same configs as the targets above.
vio-pipeline:
	@echo "Launching agent + DepthAI + OpenVINS + PX4 VIO bridge..."
	ros2 launch px4_vio_bridge vio_pipeline.launch.py \
		camera_params_file:=$(CAMERA_CONFIG) \
		openvins_config:=$(OPENVINS_CONFIG) \
		bridge_config:=$(VIO_BRIDGE_CONFIG)


oak-stream:
	@echo "Launching OAK-D Pro MJPEG stream server..."
	ros2 launch oak_stream_server oak_stream.launch.py config_path:=$(OAK_STREAM_CONFIG)


BAG_NAME ?= subset
rosrecord:
	@echo "Recording ROS topics..."
	ros2 bag record -o $(BAG_NAME) /oak/imu/data /oak/left/image_rect /oak/right/image_rect
	@echo "Recording complete. Bag file saved in the current directory under \"$(BAG_NAME)\"."

# run make rosrecord BAG_NAME=my_bag to specify the folder name

# ROS 1 conversion: only needed for Kalibr. TagSLAM reads the rosbag2 directly (tagslam-* targets).
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


# TagSLAM ground truth. These targets run in the ROS 2 Jazzy container
# (./dockerRun_tagslam.sh), which mounts the same data paths as this one: the rosbag2
# recorded here is read as it is, with no ROS 1 conversion and no copy between containers.
# Config (cameras.yaml, tagslam.yaml, camera_poses.yaml) and output live next to the
# OpenVINS ones, in rosbags/<TEST>/tagslam_v1.
# Typical use:  make tagslam-detect && make tagslam-run && make tagslam-gt
TEST ?= test_3
OPENVINS_EVAL_DIR := /root/colcon_ws/src/open_vins/ov_data/sc_fucina02/OpenVINS_eval
TAGSLAM_BAG ?= $(ROSBAG_PLAY_DIR)
TAGSLAM_DIR ?= $(OPENVINS_EVAL_DIR)/rosbags/$(TEST)/tagslam_v1
TAGSLAM_BODY ?= rig
TAGSLAM_CONFIG_ARGS = -p cameras:=$(TAGSLAM_DIR)/cameras.yaml -p tagslam_config:=$(TAGSLAM_DIR)/tagslam.yaml

# Step 1: tag detection on the raw images. Slow, needed once per bag and detector setting.
tagslam-detect:
	@echo "Detecting tags in $(TAGSLAM_BAG) -> $(TAGSLAM_DIR)/tags"
	rm -rf $(TAGSLAM_DIR)/tags
	ros2 run tagslam sync_and_detect_from_bag --ros-args \
		$(TAGSLAM_CONFIG_ARGS) \
		-p in_bag:=$(TAGSLAM_BAG) \
		-p out_bag:=$(TAGSLAM_DIR)/tags

# Step 2: TagSLAM on the detected tags; the one to repeat while tuning tagslam.yaml and
# camera_poses.yaml. max_number_of_frames must be set: tagslam_from_bag stops after the
# first message when it is left at its default 0 (it breaks out of the loop on
# getNumberOfFrames() >= max_number_of_frames). With a limit above the bag length it runs
# to the end of the bag and then writes the optimised trajectory.
tagslam-run:
	mkdir -p $(TAGSLAM_DIR)/out
	ros2 run tagslam tagslam_from_bag --ros-args \
		$(TAGSLAM_CONFIG_ARGS) \
		-p camera_poses:=$(TAGSLAM_DIR)/camera_poses.yaml \
		-p in_bag:=$(TAGSLAM_DIR)/tags \
		-p max_number_of_frames:=1000000 \
		-p output_directory:=$(TAGSLAM_DIR)/out \
		-p outbag:=$(TAGSLAM_DIR)/out/out_bag

# Step 3: trajectory of the body -> ground truth file in the ov_eval format.
tagslam-gt:
	python3 $(OPENVINS_EVAL_DIR)/extract_gt.py $(TAGSLAM_DIR)/out/out_bag \
		--topic /tagslam/odom/body_$(TAGSLAM_BODY) \
		--out $(OPENVINS_EVAL_DIR)/truths/$(TEST).txt


# ros2 bag record --max-cache-size 1073741824 -o tagslam_cantina04 /oak/imu/data /oak/left/image_rect /oak/right/image_rect