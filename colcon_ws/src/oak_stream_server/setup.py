import os
from glob import glob

from setuptools import find_packages, setup

package_name = "oak_stream_server"

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
    description="Serves a ROS 2 image topic (OAK-D Pro rectified stream) as an MJPEG HTTP stream via Flask, for viewing from a browser on the local network.",
    license="MIT",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "stream_node = oak_stream_server.stream_node:main",
        ],
    },
)
