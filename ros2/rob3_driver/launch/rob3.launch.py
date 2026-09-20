"""Launch the ROB3 driver + robot_state_publisher.

Usage:
  ros2 launch rob3_driver rob3.launch.py transport:=tcp host:=127.0.0.1 port:=54321
  ros2 launch rob3_driver rob3.launch.py transport:=serial device:=/dev/ttyUSB0
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import Command, LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    pkg = "rob3_driver"

    args = [
        DeclareLaunchArgument("transport", default_value="tcp",
                              description="'tcp' (ucSim -S socket) or 'serial'"),
        DeclareLaunchArgument("device", default_value="/dev/ttyUSB0"),
        DeclareLaunchArgument("baud", default_value="9600"),
        DeclareLaunchArgument("host", default_value="127.0.0.1"),
        DeclareLaunchArgument("port", default_value="54321"),
        DeclareLaunchArgument("publish_rate", default_value="10.0"),
        DeclareLaunchArgument("joint_prefix", default_value=""),
    ]

    urdf = Command([
        "xacro ",
        PathJoinSubstitution([FindPackageShare(pkg), "urdf", "rob3.urdf.xacro"]),
    ])

    robot_state_publisher = Node(
        package="robot_state_publisher",
        executable="robot_state_publisher",
        output="screen",
        parameters=[{"robot_description": urdf}],
    )

    driver = Node(
        package=pkg,
        executable="rob3_driver_node",
        name="rob3_driver",
        output="screen",
        parameters=[{
            "transport": LaunchConfiguration("transport"),
            "device": LaunchConfiguration("device"),
            "baud": LaunchConfiguration("baud"),
            "host": LaunchConfiguration("host"),
            "port": LaunchConfiguration("port"),
            "publish_rate": LaunchConfiguration("publish_rate"),
            "joint_prefix": LaunchConfiguration("joint_prefix"),
        }],
    )

    return LaunchDescription(args + [robot_state_publisher, driver])
