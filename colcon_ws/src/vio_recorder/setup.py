import os
from glob import glob

from setuptools import find_packages, setup

package_name = "vio_recorder"

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
    description="Records a configurable set of topics (VIO, PX4 vehicle state, OAK-D Pro images) to a rosbag2.",
    license="MIT",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "vio_recorder = vio_recorder.topic_recorder:main",
        ],
    },
)
