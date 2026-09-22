# Session logs — progress index

Dated work logs for the ROB3 firmware reverse-engineering project. This index is
the chronological overview; read a session log only when you need the specifics
(corrections, findings, and `[BYTE]`/`[SIM]`/`[HW]`/`[INFER]` provenance).

For the current project state (what exists today), see the top-level
[`../README.md`](../README.md).

| Date | Milestone | Detail |
| :--- | :-------- | :----- |
| 2026-07-14 | **Initial firmware analysis** — 5 subsystems, IRAM map, axis limits, IC complement identified from `main.asm` | [log](2026-07-14_firmware_analysis.md) |
| 2026-09-03 | **Init sequence annotated** + byte-verified (assemble-and-diff, 140 bytes, 0 mismatches); vector table corrected; serial ISR located at 0x0300 | [log](2026-09-03_annotate_init_sequence.md) |
| 2026-09-11 | **Hardware docs fixed** (74HC373, ADC0808, 74LS138 decode), **Arduino bring-ups** (teachbox + motors), **teachbox annotation** (kbd_scan/axis-select/jog), first **ucSim cl_hw module** (teachbox) | [log](2026-09-11_hardware_docs_arduino_teachbox_ucsim.md) |
| 2026-09-12 | **POS-digit direct entry** verified (decimal accumulate → axis slot); **simulator restructured** to top-level `simulator/`; **cl_adc** (EOC→INT1 free-run); **plant/bridge architecture** settled; **Teachbox GUI + CLI** | [log](2026-09-12_simulator_restructure_adc_plant_gui.md), [log](2026-09-12_teachbox_pos_digit_entry.md) |
| 2026-09-13 | **CLI UX**: configurable ROM, readline history, **ucSim console socket** (`-z <port>` + `nc` attach) | [log](2026-09-13_teachbox_cli_ux_console_socket.md) |
| 2026-09-14 | **Teachbox sim unblocked**: `run N`→`step N` (20 s→30 ms); **EMERGENCY-OFF** (P3.2) + **P3.4 poll gate** diagnosed; **loopback cl_hw module**; **keypad debounce** (release-then-hold); **ucSim bugs** filed (#001 pipelined-cmd, #002 @-filename segfault — submitted+closed upstream) | [log](2026-09-14_teachbox_sim_gates_loopback_ucsim_bug.md), [log](2026-09-14_ucsim_issue_002_at_filename_issues_relocate.md) |
| 2026-09-14 | **ucSim plugin SDK** made installable (`make install`); ROB3 modules converted to **loadable `.so` plugins** (`loadhw`) | [log](2026-09-14_ucsim_plugin_sdk_install_rob3_loadable_modules.md) |
| 2026-09-14 | **EXT1 axis servo** annotated; axis limits/calibration investigated (no per-axis clamp in ROM) | [log](2026-09-14_ext1_axis_limits_calibration_analysis.md) |
| 2026-09-16 | **Symbolic equates** (`rob3.inc`) applied to annotated files; EXT1 extracted to own file; **RS-232 shorting connector** traced (pin-4 pull-up hypothesis) | [log](2026-09-16_annotated_asm_symbolic_equates_header.md), [log](2026-09-16_ext1_axis_servo_extract_annotate_calibration.md), [log](2026-09-16_rs232_shorting_connector_trace_loopback_docs.md) |
| 2026-09-16 | **ucSim issue #001** manual-repro step added + marker rename | [log](2026-09-16_ucsim_issue_001_manual_repro_marker_rename.md) |
| 2026-09-20 | **RS-232 UART annotated** + protocol `[SIM]`-proven; **rxd cl_hw pin-driver** built (auto-baud end-to-end); fixed-baud path has no serial (ES never set); 115200 out of auto-baud range | [log](2026-09-20_rs232_annotation_protocol_sim_rxd_driver.md) |
| 2026-09-20 | **Full command set confirmed** vs ROM; **hidden commands** found (digital-input read 0x50–0x57); 0xFx replies are ACK/status not errors; **stored-program interpreter** annotated + **"hello world" program** runs | [log](2026-09-20_command_set_hidden_cmds_program_interpreter_hello_world.md) |
| 2026-09-20 | **Python ROS 2 driver** (UR-style): protocol codec, serial+TCP transports, calibration, driver node, URDF; 25 pytest tests; driver bytes verified against ROM in ucSim | [log](2026-09-20_ros2_driver_rs232.md) |
| 2026-09-22 | **Annotated source tree redesigned**: 10 region `.asm` + 7 `inc/*.inc` + `rob3.asm` top unit; old `.a51`/`gen_init.py` removed; **whole 8 KB image assembles 1:1** with the ROM (disasm51 + `d51_to_sdas.py` converter) | [log](2026-09-22_annotated_dir_redesign_assembling_1to1.md) |
| 2026-09-22 | **All 10 regions annotated** — section banners, symbolic operands, MOVC data tables marked, 0xFF padding collapsed; all regions pass standalone verify | [log](2026-09-22_annotate_all_regions_per_instruction.md) |
