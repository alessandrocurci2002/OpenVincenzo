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
depthai:
	@echo "Launching DepthAI driver..."
	ros2 launch depthai_ros_driver driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true

# Launch the DepthAI driver with only the rectified infra streams active
depthai-rectified:
	@echo "Launching DepthAI driver with rectified infra streams only..."
	ros2 launch depthai_ros_driver driver.launch.py rs_compat:=true enable_infra1:=true enable_infra2:=true enable_color:=false enable_depth:=false

# Launch OpenVINS (example subscriber)
openvins:
	@echo "Launching OpenVINS..."
	ros2 launch ov_msckf subscribe.launch.py config:=euroc_mav
