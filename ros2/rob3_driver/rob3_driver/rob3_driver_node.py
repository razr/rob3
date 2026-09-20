"""ROB3 ROS 2 driver node (Python).

UR-driver-equivalent responsibilities, over RS-232:
  * publish /joint_states (polled via the all-axis position query 0x4F)
  * a FollowJointTrajectory action server (execute a joint trajectory by
    streaming per-point position setpoints, like the UR joint-trajectory ctrl)
  * dashboard-style services: enable_motors, disable_motors, estop,
    read_serial_number  (std_srvs/Trigger)

Parameters:
  transport   : 'serial' | 'tcp'                 (default 'tcp')
  device      : serial device                    (default '/dev/ttyUSB0')
  baud        : serial baud                       (default 9600)
  host, port  : TCP endpoint for ucSim -S socket  (default 127.0.0.1:54321)
  publish_rate: /joint_states rate in Hz          (default 10.0)
  joint_prefix: prefix for joint names            (default '')

This node degrades gracefully if the transport can't be opened: it logs the
error and keeps the action/service servers up (so `ros2` graph inspection and
dry-run testing still work), reconnecting on demand.
"""
from __future__ import annotations

import math
import time
from typing import List, Optional

import rclpy
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.node import Node

from builtin_interfaces.msg import Duration as DurationMsg
from control_msgs.action import FollowJointTrajectory
from sensor_msgs.msg import JointState
from std_srvs.srv import Trigger

from .calibration import Calibration
from .rob3_interface import Rob3Client
from .transport import make_transport


class Rob3DriverNode(Node):
    def __init__(self):
        super().__init__("rob3_driver")

        # --- parameters ------------------------------------------------------
        self.declare_parameter("transport", "tcp")
        self.declare_parameter("device", "/dev/ttyUSB0")
        self.declare_parameter("baud", 9600)
        self.declare_parameter("host", "127.0.0.1")
        self.declare_parameter("port", 54321)
        self.declare_parameter("publish_rate", 10.0)
        self.declare_parameter("joint_prefix", "")

        p = self.get_parameter
        self.transport_kind = p("transport").value
        self.publish_rate = float(p("publish_rate").value)
        prefix = p("joint_prefix").value or ""

        self.cal = Calibration()
        self.joint_names = [prefix + n for n in self.cal.joint_names]

        # --- robot client ----------------------------------------------------
        transport = make_transport(
            self.transport_kind,
            device=p("device").value,
            baud=p("baud").value,
            host=p("host").value,
            port=p("port").value,
        )
        self.client = Rob3Client(transport=transport)
        self._connected = False
        self._last_counts: List[int] = [128] * 6  # mid-scale until first read
        self._connect()

        # --- ROS interfaces --------------------------------------------------
        cbg = ReentrantCallbackGroup()
        self.js_pub = self.create_publisher(JointState, "joint_states", 10)
        self.create_timer(1.0 / max(self.publish_rate, 0.1),
                          self._publish_joint_states, callback_group=cbg)

        self._traj_server = ActionServer(
            self, FollowJointTrajectory, "follow_joint_trajectory",
            execute_callback=self._execute_trajectory,
            goal_callback=self._on_goal, cancel_callback=self._on_cancel,
            callback_group=cbg,
        )

        self.create_service(Trigger, "enable_motors", self._srv_enable, callback_group=cbg)
        self.create_service(Trigger, "disable_motors", self._srv_disable, callback_group=cbg)
        self.create_service(Trigger, "estop", self._srv_estop, callback_group=cbg)
        self.create_service(Trigger, "read_serial_number", self._srv_serial, callback_group=cbg)

        self.get_logger().info(
            f"rob3_driver up (transport={self.transport_kind}, "
            f"connected={self._connected}); joints={self.joint_names}"
        )

    # ------------------------------------------------------------------ conn
    def _connect(self) -> bool:
        try:
            state = self.client.connect()
            self._connected = state in ("init_ok", "already_initialized")
            self.get_logger().info(f"handshake: {state}")
            if self._connected:
                self.client.enable_motors()
            return self._connected
        except Exception as e:  # transport open / serial import failure
            self._connected = False
            self.get_logger().warn(f"could not connect to ROB3: {e}")
            return False

    def _ensure(self) -> bool:
        return self._connected or self._connect()

    # ------------------------------------------------------------- joint pub
    def _read_counts(self) -> Optional[List[int]]:
        if not self._ensure():
            return None
        try:
            counts = self.client.read_all_positions()
        except Exception as e:
            self.get_logger().warn(f"position read failed: {e}")
            self._connected = False
            return None
        if counts:
            self._last_counts = counts
        return counts

    def _publish_joint_states(self):
        counts = self._read_counts() or self._last_counts
        positions = self.cal.counts_to_joints(counts)
        msg = JointState()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.name = list(self.joint_names)
        msg.position = [float(x) for x in positions]
        self.js_pub.publish(msg)

    # -------------------------------------------------------------- services
    def _srv_enable(self, req, resp):
        return self._trigger(resp, lambda: self.client.enable_motors(), "motors enabled")

    def _srv_disable(self, req, resp):
        return self._trigger(resp, lambda: self.client.disable_motors(), "motors disabled")

    def _srv_estop(self, req, resp):
        return self._trigger(resp, lambda: self.client.emergency_stop(), "emergency stop")

    def _srv_serial(self, req, resp):
        if not self._ensure():
            resp.success, resp.message = False, "not connected"
            return resp
        sn = self.client.read_serial_number()
        resp.success = sn is not None
        resp.message = f"serial={sn}" if sn is not None else "no reply"
        return resp

    def _trigger(self, resp, action, ok_msg):
        if not self._ensure():
            resp.success, resp.message = False, "not connected"
            return resp
        try:
            action()
            resp.success, resp.message = True, ok_msg
        except Exception as e:
            resp.success, resp.message = False, str(e)
        return resp

    # -------------------------------------------------------------- trajectory
    def _on_goal(self, goal_request):
        names = list(goal_request.trajectory.joint_names)
        if not set(names).issubset(set(self.joint_names)):
            self.get_logger().warn(f"trajectory joints {names} not a subset of {self.joint_names}")
            return GoalResponse.REJECT
        return GoalResponse.ACCEPT

    def _on_cancel(self, goal_handle):
        return CancelResponse.ACCEPT

    def _execute_trajectory(self, goal_handle):
        """Stream each trajectory point as a set of per-axis position setpoints,
        pacing by the point's time_from_start. Simple position streaming — the
        firmware's servo closes the loop to each setpoint."""
        traj = goal_handle.request.trajectory
        names = list(traj.joint_names)
        # map trajectory joint order -> our axis index
        axis_of = {n: self.joint_names.index(n) for n in names}
        result = FollowJointTrajectory.Result()

        if not self._ensure():
            result.error_code = FollowJointTrajectory.Result.INVALID_GOAL
            result.error_string = "not connected to ROB3"
            goal_handle.abort()
            return result

        t0 = time.monotonic()
        for pt in traj.points:
            if goal_handle.is_cancel_requested:
                goal_handle.canceled()
                result.error_string = "canceled"
                return result

            # build a full 6-axis count vector, keeping unspecified axes as-is
            counts = list(self._last_counts)
            for j, name in enumerate(names):
                axis = axis_of[name]
                counts[axis] = self.cal.joint_to_count(axis, pt.positions[j])

            # pace to the point's time_from_start
            target_t = _dur_to_sec(pt.time_from_start)
            sleep = target_t - (time.monotonic() - t0)
            if sleep > 0:
                time.sleep(sleep)

            try:
                self.client.set_all_positions(counts)
                self._last_counts = counts
            except Exception as e:
                result.error_code = FollowJointTrajectory.Result.PATH_TOLERANCE_VIOLATED
                result.error_string = f"send failed: {e}"
                self._connected = False
                goal_handle.abort()
                return result

            fb = FollowJointTrajectory.Feedback()
            fb.joint_names = names
            goal_handle.publish_feedback(fb)

        result.error_code = FollowJointTrajectory.Result.SUCCESSFUL
        goal_handle.succeed()
        return result

    def destroy_node(self):
        try:
            self.client.close()
        except Exception:
            pass
        super().destroy_node()


def _dur_to_sec(d: DurationMsg) -> float:
    return float(d.sec) + float(d.nanosec) * 1e-9


def main(args=None):
    rclpy.init(args=args)
    node = Rob3DriverNode()
    from rclpy.executors import MultiThreadedExecutor

    executor = MultiThreadedExecutor()
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
