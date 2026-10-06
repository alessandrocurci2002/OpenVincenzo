import os
from glob import glob

from setuptools import find_packages, setup

package_name = "px4_vio_bridge"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        (os.path.join("share", package_name, "launch"), glob("launch/*.launch.py")),
        (os.path.join("share", package_name, "config"), glob("config/*.yaml")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Alessandro Curci",
    maintainer_email="alessandrocurci2002@gmail.com",
    description="Bridges OpenVINS odomimu (nav_msgs/Odometry) into PX4's VehicleOdometry (uXRCE-DDS) with FRD frame conversion.",
    license="MIT",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "vio_to_px4_bridge = px4_vio_bridge.vio_to_px4_bridge:main",
            "wait_for_topics = px4_vio_bridge.wait_for_topics:main",
        ],
    },
)
