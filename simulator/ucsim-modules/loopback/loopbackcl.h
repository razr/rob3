/*
 * ucsim RS-232-shorting-connector / MM74C04N #1 loopback peripheral for the
 * ROB3 board (header).
 *
 * Models the pin-level effect of the required "RS-232 shorting connector":
 * on the real board the emergency-off line (P3.2/INT0) and the teachbox-poll
 * enable (P3.4/T0) — both conditioned by MM74C04N #1 — read HIGH when the
 * shorting connector is present. Without it the firmware sits in the
 * EMERGENCY-OFF handler and never polls the keypad. This module drives those
 * P3 input pins HIGH so the ROM runs as it does on a properly-connected bench.
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

/* End of s51.src/loopbackcl.h */
