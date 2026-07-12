# ROB3 Hardware Manuals & Reference Guides

This directory contains the original, scanned reference manuals and operational documentation for the ROB3 articulated robotic arm. These files serve as the ground truth for understanding the physical dimensions, electrical requirements, and safety protocols of the hardware.

## Available Documents

*   **[TBPS.pdf](docs/manuals/TBPS.pdf)** — User's manual for ROB 3i.

## Quick Hardware Reference (From Manuals)

*   **Total Axes:** 5 revolute joints + 1 gripper.
*   **Actuator Type:** DC Servo Motors.
*   **Feedback Mechanism:** Absolute potentiometric rotary position transducers.
*   **Payload Capacity:** *[Insert weight limit if known, e.g., 0.5 kg]*
*   **Maximum Reach:** *[Insert reach radius if known, e.g., 450 mm]*

## Purpose in this Project

These documents are preserved here to assist with two primary phases of development:

1.  **Kinematics & Control:** Calculating the exact link lengths and joint coordinate systems needed to build the **ROS 2 URDF (Robot Description Model)**, ensuring software safety limits match the physical capabilities of the arm.
2.  **Low-Level Integration:** Providing the explicit **RS232 communication protocol** requirements. This serves as the blueprint for reverse-engineering the 8031 microcontroller binary and writing the serial bridge node for the ROS 2 hardware interface.
