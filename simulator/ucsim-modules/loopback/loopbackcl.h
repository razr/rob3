/*
 * ucsim RS-232-shorting-connector / MM74C04N #1 loopback peripheral for the
 * ROB3 board (header) — LOADABLE PLUGIN version.
 *
 * Simulation aid, NOT a wiring-accurate connector model. It forces the two
 * Port-3 GATE inputs the firmware waits on — P3.4 (T0, teachbox-poll enable)
 * and P3.2 (INT0, EMERGENCY-OFF) — to the level that lets the ROM leave the
 * EMERGENCY-OFF handler and reach the keypad poll. It does NOT echo TX<->RX
 * (P3.0/RXD is left alone) and it does NOT reproduce the connector's real DB9
 * strap (whose exact wiring/polarity is still unresolved — see
 * hardware/connectors/rs232-shorting-connector.md). It drives the 8031-pin end
 * state HIGH, which is the correct outcome for the sim regardless of how the
 * real connector achieves it.
 */

#ifndef LOOPBACK_HEADER
#define LOOPBACK_HEADER

#include "stypes.h"
#include "uccl.h"
#include "hwcl.h"
#include "newcmdcl.h"

class cl_loopback: public cl_hw
{
public:
  int enabled;               // 1 = drive the conditioned P3 pins HIGH
  t_mem drive_mask;          // which P3 bits to force HIGH (default P3.2|P3.4)
  class cl_memory_cell *cell_p3;
  class cl_memory_cell *cell_bit2;   // bits-space cell for P3.2 (0xB2)
  class cl_memory_cell *cell_bit4;   // bits-space cell for P3.4 (0xB4)
public:
  cl_loopback(class cl_uc *auc);
  virtual int init(void);

  virtual int tick(int cycles);
  virtual t_mem read(class cl_memory_cell *cell);

  virtual bool set_cmd(class cl_cmdline *cmdline, class cl_console_base *con);
  virtual void print_info(class cl_console_base *con);
};

#endif

/* End of loopbackcl.h */
