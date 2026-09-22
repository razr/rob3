/*
 * ucsim RS-232-shorting-connector / MM74C04N #1 loopback peripheral for ROB3.
 *
 * NAMING / SCOPE (read this first)
 *   Despite the name, this does NOT model an RS-232 *data* loopback (TX<->RX
 *   echo on P3.0/RXD). It models only the *pin-level side effect* the ROB3
 *   "9-pin shorting connector" has via MM74C04N #1: forcing the two Port-3
 *   GATE inputs the firmware waits on to the level that lets the ROM reach the
 *   Teachbox poll. Modelling a real TX<->RX echo would be WRONG here: the
 *   blocking gates are P3.2 (EMERGENCY-OFF) and P3.4 (poll enable), NOT P3.0.
 *   Full electrical trace + the still-open "why is the connector required"
 *   question: hardware/connectors/rs232-shorting-connector.md.
 *
 * WHY THIS EXISTS
 *   The ROB3 controller only runs when BOTH the Teachbox AND the "RS-232
 *   shorting connector" are installed (hardware/teachbox/README.md, "Hardware
 *   requirements"). Electrically, MM74C04N #1 (hardware/board/MM74C04N.md)
 *   conditions three 8031 Port-3 inputs:
 *       P3.2 (INT0)  <- DB25 pin 4 EMERGENCY-OFF (active LOW)
 *       P3.4 (T0)                    teachbox-poll enable gate
 *       P3.0 (RXD)                   baud strap
 *   With the shorting connector present these lines sit HIGH; the firmware
 *   then (a) leaves the EMERGENCY-OFF handler (0x0040), and (b) passes the
 *   `JB P3.4, tb_poll` gate at 0x07AB so the keypad scanner is called.
 *
 *   In ucSim an undriven input pin reads LOW, so without help the ROM traps in
 *   the emergency-off spin and never polls the keypad (see the annotated
 *   main-loop "THREE GATES" note in firmware/src/annotated/main.asm,
 *   and rob3-lessons-learned). This module reproduces the "connector present"
 *   pin state by driving the conditioned P3 bits HIGH on read.
 *
 * WHAT IT DOES
 *   Registers the P3 SFR cell (0xB0) AND the bits-space cells for P3.2 (0xB2)
 *   and P3.4 (0xB4). The 8051 bit instructions (JB/JNB/…) read the pin through
 *   the "bits" address space via cl_port::read, which returns
 *   (latch_bit && port_pins_bit) — so a competing operator that returns 1 is
 *   needed to make an undriven input read HIGH. Because cl_memory_cell::read()
 *   returns the LAST registered operator's value and this module is added after
 *   the core cl_port, our read() wins on the P3.2/P3.4 bit cells. On the P3
 *   byte cell we OR the drive_mask in for consistency. P3.0 is left alone so
 *   the harness can still select the fixed-baud path (P3.0 = 0).
 *
 * COMMANDS
 *   set hardware loopback on|off        enable/disable the drive (default on)
 *   set hardware loopback <maskbyte>    set which P3 bits to force HIGH
 *
 * This is a LOADABLE ucsim plugin (built against the installed ucSim SDK and
 * loaded at runtime with `loadhw loopback.so`). See ../README.md.
 */

#include <stdio.h>
#include <string.h>
#include "ucsim_hw_plugin.h"
#include "argcl.h"
#include "regs51.h"
#include "types51.h"
#include "loopbackcl.h"

#define P3_INT0  0x04   /* P3.2 -> INT0 / EMERGENCY-OFF        */
#define P3_T0    0x10   /* P3.4 -> T0 / teachbox-poll enable   */

cl_loopback::cl_loopback(class cl_uc *auc):
  cl_hw(auc, HW_GPIO, 0, "loopback")
{
  enabled = 1;
  drive_mask = P3_INT0 | P3_T0;   // 0x14
  cell_p3 = 0;
  cell_bit2 = 0;
  cell_bit4 = 0;
}

int
cl_loopback::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr = uc->address_space(MEM_SFR_ID);
  class cl_address_space *bas = uc->address_space("bits");
  if (sfr)
    cell_p3 = register_cell(sfr, P3);          // P3 byte = 0xB0
  if (bas)
    {
      cell_bit2 = register_cell(bas, 0xB2);    // P3.2 (INT0 / EMERGENCY-OFF)
      cell_bit4 = register_cell(bas, 0xB4);    // P3.4 (T0 / teachbox-poll gate)
    }
  return 0;
}

t_mem
cl_loopback::read(class cl_memory_cell *cell)
{
  if (!enabled)
    return cell->get();
  if (cell == cell_bit2 || cell == cell_bit4)
    return 1;                          // conditioned input pin reads HIGH
  if (cell == cell_p3)
    return cell->get() | drive_mask;   // byte read: OR the driven bits in
  return cell->get();
}

// Hold the conditioned P3 latch bits HIGH every tick. This models an external
// driver (the RS-232 shorting connector via MM74C04N #1) holding P3.2/P3.4
// high, and — unlike a read-only operator — it feeds ALL the paths that sample
// P3: the firmware's JB/JNB bit reads, the byte read sfr->read(P3), and the
// interrupt controller's level-triggered INT0/INT1 tracking (which follows the
// port latch/value via change events). Without this the level-triggered INT0
// keeps re-vectoring to the EMERGENCY-OFF handler because the firmware's own
// writes to the P3 latch pull P3.2 back to 0.
int
cl_loopback::tick(int cycles)
{
  if (enabled && cell_p3)
    {
      t_mem v = cell_p3->get();
      if ((v & drive_mask) != drive_mask)
	{
	  t_mem nv = v | drive_mask;
	  // Write THROUGH the cell (dispatches to cl_port::write), so the port
	  // fires EV_PORT_CHANGED and the interrupt controller re-samples
	  // bit_INT0/bit_INT1 = (pins & value). Using cell->set() would update
	  // the latch silently and the level-triggered INT0 would keep firing.
	  cell_p3->write(nv);
	}
    }
  return 0;
}

// set hardware loopback on|off        (or)   set hardware loopback <maskbyte>
bool
cl_loopback::set_cmd(class cl_cmdline *cmdline, class cl_console_base *con)
{
  class cl_cmd_arg *p0 = cmdline->param(0);
  if (cmdline->syntax_match(uc, STRING))
    {
      const char *s = p0->value.string.string;
      if (s && (strcmp(s, "on") == 0 || strcmp(s, "ON") == 0))
	{ enabled = 1; con->dd_printf("loopback: on (P3 mask=0x%02x)\n",
				      (unsigned)drive_mask); return true; }
      if (s && (strcmp(s, "off") == 0 || strcmp(s, "OFF") == 0))
	{ enabled = 0; con->dd_printf("loopback: off\n"); return true; }
      return false;
    }
  if (cmdline->syntax_match(uc, NUMBER))
    {
      drive_mask = p0->value.number & 0xff;
      enabled = 1;
      con->dd_printf("loopback: on (P3 mask=0x%02x)\n", (unsigned)drive_mask);
      return true;
    }
  return false;
}

void
cl_loopback::print_info(class cl_console_base *con)
{
  con->dd_printf("%s[%d]\n", id_string, id);
  con->dd_printf("  enabled=%d  P3 drive mask=0x%02x (P3.2 EMO, P3.4 pollgate)\n",
		 enabled, (unsigned)drive_mask);
}

UCSIM_HW_PLUGIN(cl_loopback)

/* End of loopback.cc */
