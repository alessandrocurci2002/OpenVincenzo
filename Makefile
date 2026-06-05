IMAGE ?= openvincenzo:humble
OAK_IMAGE ?= openvincenzo:humble-oak
ARM_IMAGE ?= openvincenzo:humble-arm64
OAK_ARM_IMAGE ?= openvincenzo:humble-oak-arm64
PLATFORM ?= linux/arm64/v8
BUILDX_GIT_INFO ?= 0
DOCKER ?= docker

RUN_PX4_SETUP ?= 0
BUILD_OPENVINS ?= 0
ROS_DOMAIN_ID ?= 0
RUN_ROS_GZ_BRIDGES ?= 0

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
	@echo "  make setup-px4-host     Initialize/update the PX4-Autopilot submodule"
	@echo "  make patch-px4-gz-host  Apply PX4 Gazebo model compatibility patches"
	@echo "  make clean-px4-build-host Remove stale PX4 SITL build cache"
	@echo "  make setup-oak-host     Install Luxonis udev rule on the Raspberry Pi host"
	@echo "  make check-scripts      Validate shell script syntax"
	@echo ""
	@echo "Useful overrides:"
	@echo "  make run RUN_PX4_SETUP=0 BUILD_OPENVINS=0"
	@echo "  make run RUN_ROS_GZ_BRIDGES=1"
	@echo "  make build IMAGE=my-image:tag"
	@echo "  make oak-stereo OAK_LAUNCH_FILE=driver.launch.py"

.PHONY: build
build:
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) build --target production -t $(IMAGE) .

.PHONY: build-oak
build-oak:
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) build --target oak -t $(OAK_IMAGE) .

.PHONY: build-arm64
build-arm64:
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) buildx build --platform $(PLATFORM) --target production -t $(ARM_IMAGE) --load .

.PHONY: build-oak-arm64
build-oak-arm64:
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) buildx build --platform $(PLATFORM) --target oak -t $(OAK_ARM_IMAGE) --load .

.PHONY: ensure-image
ensure-image:
	@$(DOCKER) image inspect $(IMAGE) >/dev/null 2>&1 || { \
		echo "Image $(IMAGE) not found. Build it first with: make build"; \
		exit 1; \
	}

.PHONY: ensure-oak-image
ensure-oak-image:
	@$(DOCKER) image inspect $(OAK_IMAGE) >/dev/null 2>&1 || { \
		echo "Image $(OAK_IMAGE) not found. Build it first with: make build-oak"; \
		exit 1; \
	}

.PHONY: run
run: ensure-image
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) RUN_ROS_GZ_BRIDGES=$(RUN_ROS_GZ_BRIDGES) \
		$(RUNNER) $(CONTAINER) $(IMAGE)

.PHONY: shell
shell: ensure-image
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) RUN_ROS_GZ_BRIDGES=$(RUN_ROS_GZ_BRIDGES) \
		$(RUNNER) $(CONTAINER) $(IMAGE) bash

.PHONY: rviz
rviz: ensure-image
	chmod +x $(RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) RUN_ROS_GZ_BRIDGES=$(RUN_ROS_GZ_BRIDGES) \
		$(RUNNER) $(CONTAINER) $(IMAGE) rviz2

.PHONY: run-full
run-full:
	$(MAKE) run RUN_PX4_SETUP=1 BUILD_OPENVINS=1

.PHONY: shell-full
shell-full:
	$(MAKE) shell RUN_PX4_SETUP=1 BUILD_OPENVINS=1

.PHONY: smoke
smoke: ensure-image
	chmod +x $(RUNNER)
	RUN_PX4_SETUP=0 BUILD_OPENVINS=0 \
		$(RUNNER) $(SMOKE_CONTAINER) $(IMAGE) smoke_no_oak

.PHONY: oak-stereo
oak-stereo: ensure-oak-image
	chmod +x $(OAK_RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) RUN_ROS_GZ_BRIDGES=$(RUN_ROS_GZ_BRIDGES) OAK_LAUNCH_FILE=$(OAK_LAUNCH_FILE) \
		$(OAK_RUNNER) $(OAK_CONTAINER) $(OAK_IMAGE) run_oak_stereo

.PHONY: run-oak
run-oak: oak-stereo

.PHONY: oak-shell
oak-shell: ensure-oak-image
	chmod +x $(OAK_RUNNER)
	ROS_DOMAIN_ID=$(ROS_DOMAIN_ID) RUN_PX4_SETUP=$(RUN_PX4_SETUP) BUILD_OPENVINS=$(BUILD_OPENVINS) RUN_ROS_GZ_BRIDGES=$(RUN_ROS_GZ_BRIDGES) \
		$(OAK_RUNNER) $(OAK_CONTAINER) $(OAK_IMAGE) bash

.PHONY: smoke-oak
smoke-oak: ensure-oak-image
	chmod +x $(OAK_RUNNER)
	RUN_PX4_SETUP=0 BUILD_OPENVINS=0 OAK_LAUNCH_FILE=$(OAK_LAUNCH_FILE) OAK_BOOT_SECONDS=$(OAK_BOOT_SECONDS) \
		$(OAK_RUNNER) $(OAK_SMOKE_CONTAINER) $(OAK_IMAGE) smoke_oak

.PHONY: setup-oak-host
setup-oak-host:
	echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="03e7", MODE="0666"' | sudo tee /etc/udev/rules.d/80-movidius.rules
	sudo udevadm control --reload-rules
	sudo udevadm trigger

.PHONY: setup-px4-host
setup-px4-host:
	@set -e; \
	PX4_PATH="$$(git config -f .gitmodules --get submodule.PX4-Autopilot.path)"; \
	PX4_BRANCH="$$(git config -f .gitmodules --get submodule.PX4-Autopilot.branch)"; \
	test -n "$$PX4_PATH"; \
	test -n "$$PX4_BRANCH"; \
	git submodule sync --recursive "$$PX4_PATH"; \
	git submodule update --init --recursive "$$PX4_PATH"; \
	git -C "$$PX4_PATH" fetch origin "$$PX4_BRANCH"; \
	git -C "$$PX4_PATH" checkout "$$PX4_BRANCH"; \
	git -C "$$PX4_PATH" pull --ff-only origin "$$PX4_BRANCH"; \
	git -C "$$PX4_PATH" submodule sync --recursive; \
	git -C "$$PX4_PATH" submodule update --init --recursive; \
	PX4_DIR="$$PX4_PATH" scripts/patch_px4_gz_models.sh

.PHONY: patch-px4-gz-host
patch-px4-gz-host:
	@set -e; \
	PX4_PATH="$$(git config -f .gitmodules --get submodule.PX4-Autopilot.path)"; \
	test -n "$$PX4_PATH"; \
	PX4_DIR="$$PX4_PATH" scripts/patch_px4_gz_models.sh

.PHONY: clean-px4-build-host
clean-px4-build-host:
	@set -e; \
	PX4_PATH="$$(git config -f .gitmodules --get submodule.PX4-Autopilot.path)"; \
	test -n "$$PX4_PATH"; \
	$(MAKE) -C "$$PX4_PATH" distclean

.PHONY: check-scripts
check-scripts:
	for f in entrypoint.sh dockerRun.sh dockerRun_oak.sh scripts/smoke_no_oak.sh scripts/smoke_oak.sh scripts/run_oak_stereo.sh scripts/patch_px4_gz_models.sh scripts/run_px4_baylands_H1.sh scripts/setup_px4_repo.sh scripts/setup_px4_deps.sh; do \
		bash -n "$$f"; \
	done

.PHONY: check-dockerfile
check-dockerfile:
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) build --check --target production .
	BUILDX_GIT_INFO=$(BUILDX_GIT_INFO) $(DOCKER) build --check --target oak .

.PHONY: ps
ps:
	$(DOCKER) ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
