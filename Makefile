IMAGE ?= openvincenzo:humble
OAK_IMAGE ?= openvincenzo:humble-oak
ARM_IMAGE ?= openvincenzo:humble-arm64
OAK_ARM_IMAGE ?= openvincenzo:humble-oak-arm64
PLATFORM ?= linux/arm64/v8

RUN_PX4_SETUP ?= 0
BUILD_OPENVINS ?= 0
ROS_DOMAIN_ID ?= 0

OAK_LAUNCH_FILE ?= rgbd_pcl.launch.py
OAK_BOOT_SECONDS ?= 10

STAMP := $(shell date +%Y%m%d-%H%M%S)
CONTAINER ?= ov-$(STAMP)
OAK_CONTAINER ?= ov-oak-$(STAMP)
SMOKE_CONTAINER ?= ov-smoke-$(STAMP)
OAK_SMOKE_CONTAINER ?= ov-oak-smoke-$(STAMP)

RUNNER := ./dockerRun.sh
OAK_RUNNER := ./dockerRun_oak.sh

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "OpenVincenzo Docker commands"
	@echo ""
	@echo "Build:"
	@echo "  make build              Build production image without OAK-D Pro support"
	@echo "  make build-oak          Build image with OAK-D Pro / DepthAI ROS support"
	@echo "  make build-arm64        Cross-build production image for Raspberry Pi 5"
	@echo "  make build-oak-arm64    Cross-build OAK-D Pro image for Raspberry Pi 5"
	@echo ""
	@echo "Smoke tests:"
	@echo "  make smoke              Test image without PX4/OpenVINS runtime setup"
	@echo "  make smoke-oak          Test OAK-D Pro image and live USB camera"
	@echo ""
	@echo "Run:"
	@echo "  make run                Start the production container"
	@echo "  make shell              Open bash in the production container"
	@echo "  make rviz               Start RViz2 in the production container"
	@echo "  make run-full           Start production container and run PX4/OpenVINS setup"
	@echo "  make shell-full         Open bash after PX4/OpenVINS setup"
	@echo "  make oak-stereo         Start the OAK-D Pro stereo driver"
	@echo "  make oak-shell          Open bash in the OAK-D Pro container"
	@echo ""
	@echo "Host setup:"
	@echo "  make setup-oak-host     Install Luxonis udev rule on the Raspberry Pi host"
	@echo "  make check-scripts      Validate shell script syntax"
	@echo ""
	@echo "Useful overrides:"
	@echo "  make run RUN_PX4_SETUP=0 BUILD_OPENVINS=0"
	@echo "  make build IMAGE=my-image:tag"
	@echo "  make oak-stereo OAK_LAUNCH_FILE=driver.launch.py"

.PHONY: build
build:
	docker build --target production -t $(IMAGE) .

.PHONY: build-oak
build-oak:
	docker build --target oak -t $(OAK_IMAGE) .

.PHONY: build-arm64
build-arm64:
	docker buildx build --platform $(PLATFORM) --target production -t $(ARM_IMAGE) --load .

.PHONY: build-oak-arm64
build-oak-arm64:
	docker buildx build --platform $(PLATFORM) --target oak -t $(OAK_ARM_IMAGE) --load .

.PHONY: run
run:
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) \
		$(RUNNER) $(CONTAINER) $(IMAGE)

.PHONY: shell
shell:
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) \
		$(RUNNER) $(CONTAINER) $(IMAGE) bash

.PHONY: rviz
rviz:
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) \
		$(RUNNER) $(CONTAINER) $(IMAGE) rviz2

.PHONY: run-full
run-full:
	$(MAKE) run RUN_PX4_SETUP=1 BUILD_OPENVINS=1

.PHONY: shell-full
shell-full:
	$(MAKE) shell RUN_PX4_SETUP=1 BUILD_OPENVINS=1

.PHONY: smoke
smoke:
	chmod +x $(RUNNER)
	RUN_PX4_SETUP=0 BUILD_OPENVINS=0 \
		$(RUNNER) $(SMOKE_CONTAINER) $(IMAGE) smoke_no_oak

.PHONY: oak-stereo
oak-stereo:
	chmod +x $(OAK_RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) OAK_LAUNCH_FILE=$(OAK_LAUNCH_FILE) \
		$(OAK_RUNNER) $(OAK_CONTAINER) $(OAK_IMAGE) run_oak_stereo

.PHONY: run-oak
run-oak: oak-stereo

.PHONY: oak-shell
oak-shell:
	chmod +x $(OAK_RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) \
		$(OAK_RUNNER) $(OAK_CONTAINER) $(OAK_IMAGE) bash

.PHONY: smoke-oak
smoke-oak:
	chmod +x $(OAK_RUNNER)
	RUN_PX4_SETUP=0 BUILD_OPENVINS=0 OAK_LAUNCH_FILE=$(OAK_LAUNCH_FILE) OAK_BOOT_SECONDS=$(OAK_BOOT_SECONDS) \
		$(OAK_RUNNER) $(OAK_SMOKE_CONTAINER) $(OAK_IMAGE) smoke_oak

.PHONY: setup-oak-host
setup-oak-host:
	echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="03e7", MODE="0666"' | sudo tee /etc/udev/rules.d/80-movidius.rules
	sudo udevadm control --reload-rules
	sudo udevadm trigger

.PHONY: check-scripts
check-scripts:
	for f in entrypoint.sh dockerRun.sh dockerRun_oak.sh scripts/smoke_no_oak.sh scripts/smoke_oak.sh scripts/run_oak_stereo.sh; do \
		bash -n "$$f"; \
	done

.PHONY: check-dockerfile
check-dockerfile:
	docker build --check --target production .
	docker build --check --target oak .

.PHONY: ps
ps:
	docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
