/*
 * ucsim RXD bit-banger for ROB3 — drives the 8031 P3.0 (RXD) pin at bit level.
 *
 * WHY THIS EXISTS
 * ---------------
 * ucSim's MCS-51 UART model (core: cl_serial, src/sims/s51.src/serial.cc)
 * works at the BYTE/FRAME level: it delivers a whole received byte into SBUF
 * and sets RI after a frame-time, and it NEVER drives the P3.0 (RXD) or P3.1
 * (TXD) pins. That is the right abstraction for normal firmware that uses the
 * UART through SBUF/RI/TI.
 *
 * The ROB3 firmware, however, AUTO-DETECTS the host baud rate before it turns
 * the UART on. Its init path (P3.0 read HIGH at 0x06A7) enters a measure loop
 * that treats P3.0 as a RAW GPIO and times the incoming byte's bit edges with
 * Timer 0:
 *     0x06BF:  JB P3.0, 0x06BF     ; spin until RXD start bit (P3.0 goes LOW)
 *     ...      (record TL0/TH0 per edge, validate the pattern == 0x20,
 *               derive TH1 = ~(width-1), start TR1, then IE=0x17 (ES on))
 * Because ucSim's UART never toggles P3.0, that loop spins forever and the
 * firmware can never leave auto-detect — so the serial subsystem cannot be
 * exercised end-to-end in stock ucSim. See simulator/issues/003-*.
 *
 * WHAT THIS MODULE DOES
 * ---------------------
 * It is the missing bit-level RXD line. On command it shifts one byte out on
 * P3.0 as a standard 8N1 UART frame, at a configurable baud, synchronized to
 * CPU cycles:
 *     idle:  P3.0 = 1 (HIGH)
 *     frame: [START=0][D0][D1]..[D7]  (LSB first) [STOP=1]
 * Each bit is held for  bit_clocks = cpu_clock / baud  CPU clock ticks. tick()
 * receives MACHINE cycles; on cl_uc51 one machine cycle = 12 clocks
 * (clock_per_cycle()==12), so bit_clocks is accumulated as cycles*12.
 *
 * At XTAL 11.0592 MHz, 115200 baud -> 11059200/115200 = 96 clocks/bit = exactly
 * 8 machine cycles/bit, which is what ROB3's host uses.
 *
 * Like the loopback module, P3.0 is driven THROUGH the port write path
 * (cell->write) so the change is seen by every sampler (JB/JNB bit reads, the
 * byte read, and the core UART's own reception if it later samples the pin).
 *
 * IMPORTANT SCOPE
 *   This drives ONLY the physical RXD pin so the firmware's software
 *   bit-sampling auto-baud loop works. It does NOT feed SBUF directly (that is
 *   the core UART's job once the firmware has configured the real receiver).
 *   For the ROB3 auto-detect, the training byte 0x20 shifted here lets the
 *   measure loop compute TH1 and turn the UART on.
 *
 * COMMANDS
 *   set hardware rxd <byte> [baud]   queue a byte (0..255) to shift out on P3.0
 *                                    at [baud] bits/s (default 115200).
 *   set hardware rxd                 (no args) print state.
 *   set hardware rxd idle            force the line back to idle HIGH.
 *
 * This is a LOADABLE ucsim plugin (built against the installed ucSim SDK and
 * loaded at runtime with `loadhw rxd.so`). See ../README.md.
 */

#include <stdio.h>
#include <string.h>
#include "ucsim_hw_plugin.h"
#include "argcl.h"
#include "regs51.h"
#include "types51.h"
#include "rxdcl.h"

#define P3_RXD_BIT   0   /* P3.0 = RXD                                   */
#define P3_RXD_MASK  0x01
/* Default bit time in MACHINE CYCLES. At 11.0592 MHz, 115200 baud:
 *   11059200 / 115200 = 96 CPU clocks/bit; /12 clocks-per-cycle = 8 cycles/bit. */
#define DEFAULT_CYCLES_PER_BIT 8

cl_rxd::cl_rxd(class cl_uc *auc):
  cl_hw(auc, HW_GPIO, 1, "rxd")   /* id 1 to avoid colliding with loopback id 0 */
{
  cell_p3   = 0;
  cell_bit0 = 0;
  cyc_per_bit= DEFAULT_CYCLES_PER_BIT;
  frame_bits= 0;
  cur_bit   = -1;                 /* -1 = idle, not transmitting */
  cyc_acc   = 0;
  frame     = 0;
}

int
cl_rxd::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr = uc->address_space(MEM_SFR_ID);
  class cl_address_space *bas = uc->address_space("bits");
  if (sfr)
    cell_p3 = register_cell(sfr, P3);           /* P3 byte = 0xB0 */
  if (bas)
    cell_bit0 = register_cell(bas, 0xB0);       /* P3.0 bit cell   */
  drive(1);                                     /* idle line HIGH */
  return 0;
}

/* Drive P3.0 to `level` through the port write path so the change fires the
 * usual events and is seen by JB/JNB and the byte read. Preserve the other P3
 * bits from the current latch value. */
void
cl_rxd::drive(int level)
{
  if (!cell_p3)
    return;
  t_mem v = cell_p3->get();
  t_mem nv = level ? (v | P3_RXD_MASK) : (v & ~P3_RXD_MASK);
  if (nv != v)
    cell_p3->write(nv);
}

int
cl_rxd::tick(int cycles)
{
  if (cur_bit < 0)
    return 0;                       /* idle: nothing to shift */

  cyc_acc += cycles;                /* accumulate MACHINE cycles */
  while (cur_bit >= 0 && cyc_acc >= cyc_per_bit)
    {
      cyc_acc -= cyc_per_bit;
      cur_bit++;
      if (cur_bit >= frame_bits)
	{
	  /* frame done: return to idle HIGH */
	  cur_bit = -1;
	  drive(1);
	  break;
	}
      drive((frame >> cur_bit) & 1);
    }
  return 0;
}

/* Build an 8N1 frame in `frame`: bit0 = START(0), bits1..8 = data LSB-first,
 * bit9 = STOP(1). Begin transmitting from bit 0 (the start bit). */
void
cl_rxd::queue_byte(u8_t b)
{
  frame = 0;
  /* bit 0 = start = 0 (already 0) */
  frame |= ((t_mem)b) << 1;         /* data bits 1..8, LSB at bit 1 */
  frame |= ((t_mem)1) << 9;         /* stop bit = 1 */
  frame_bits = 10;                  /* 1 start + 8 data + 1 stop */
  cur_bit = 0;
  cyc_acc = 0;
  drive(0);                         /* assert the start bit now */
}

// set hardware rxd <byte> [cycles_per_bit] | set hardware rxd idle | (no args)
//   cycles_per_bit is the bit time in MACHINE cycles. The harness computes it
//   as  xtal / baud / clock_per_cycle  (e.g. 11.0592MHz / 115200 / 12 = 8).
bool
cl_rxd::set_cmd(class cl_cmdline *cmdline, class cl_console_base *con)
{
  class cl_cmd_arg *p0 = cmdline->param(0);
  class cl_cmd_arg *p1 = cmdline->param(1);

  /* "idle" -> force line HIGH, cancel any transmit */
  if (cmdline->syntax_match(uc, STRING))
    {
      const char *s = p0->value.string.string;
      if (s && strcmp(s, "idle") == 0)
	{ cur_bit = -1; drive(1); con->dd_printf("rxd: idle (P3.0 HIGH)\n"); return true; }
      return false;
    }

  /* "<byte> <cycles_per_bit>" */
  if (cmdline->syntax_match(uc, NUMBER NUMBER))
    {
      int c = (int)p1->value.number;
      if (c >= 1) cyc_per_bit = c;
      queue_byte((u8_t)(p0->value.number & 0xff));
      con->dd_printf("rxd: shifting 0x%02x @ %d cycles/bit\n",
		     (unsigned)(p0->value.number & 0xff), cyc_per_bit);
      return true;
    }
  /* "<byte>" (use current/default cycles_per_bit) */
  if (cmdline->syntax_match(uc, NUMBER))
    {
      queue_byte((u8_t)(p0->value.number & 0xff));
      con->dd_printf("rxd: shifting 0x%02x @ %d cycles/bit\n",
		     (unsigned)(p0->value.number & 0xff), cyc_per_bit);
      return true;
    }

  print_info(con);
  return true;
}

void
cl_rxd::print_info(class cl_console_base *con)
{
  con->dd_printf("%s[%d]\n", id_string, id);
  con->dd_printf("  cycles/bit=%d  state=%s  cur_bit=%d\n",
		 cyc_per_bit, (cur_bit < 0 ? "idle" : "shifting"), cur_bit);
}

UCSIM_HW_PLUGIN(cl_rxd)

/* End of rxd.cc */
