.PHONY: help depthai depthai-rectified openvins

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
	ros2 launch depthai_ros_driver_v3 driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true use_rviz:=true

depthai:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true

# Launch the DepthAI driver with only the rectified infra streams active
depthai-rectified:
	@echo "Launching DepthAI driver with rectified infra streams only..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true enable_color:=false enable_depth:=false

depthai-rectified-rviz:
	@echo "Launching DepthAI driver with rectified infra streams only..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true enable_color:=false enable_depth:=false use_rviz:=true

# Launch OpenVINS (example subscriber)
openvins:
	@echo "Launching OpenVINS..."
	ros2 launch ov_msckf subscribe.launch.py config:=euroc_mav


depthai-rviz:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		rs_compat:=true \
		enable_infra1:=true \
		enable_infra2:=true \
		pointcloud.enable:=true \
		camera.i_enable_imu:=true \
		use_rviz:=true

depthai:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver_v3 driver.launch.py \
		rs_compat:=true \
		enable_infra1:=true \
		enable_infra2:=true \
		pointcloud.enable:=true \
		camera.i_enable_imu:=true

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
	ros2 launch ov_msckf subscribe.launch.py config:=euroc_mav