from setuptools import find_packages, setup
import os
from glob import glob

package_name = "rob3_driver"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages",
         ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        (os.path.join("share", package_name, "launch"), glob("launch/*.launch.py")),
        (os.path.join("share", package_name, "config"), glob("config/*.yaml")),
        (os.path.join("share", package_name, "urdf"), glob("urdf/*")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="ROB3 project",
    maintainer_email="dev@example.com",
    description="ROS 2 driver for the Eurobtec ROB 3 over RS-232 (Python).",
    license="See repository LICENSE",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "rob3_driver_node = rob3_driver.rob3_driver_node:main",
        ],
    },
)
