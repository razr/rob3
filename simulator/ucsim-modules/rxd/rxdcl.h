/*
 * ucsim RXD bit-banger for the ROB3 board (header) — LOADABLE PLUGIN.
 *
 * Drives the 8031 P3.0 (RXD) pin at BIT level so the firmware's software
 * auto-baud measure loop (which polls the raw P3.0 pin with `JB P3.0,$` and
 * times edges with Timer 0) can run in ucSim. ucSim's core UART is byte-level
 * and never toggles P3.0; this module supplies the missing pin activity.
 *
 * Shifts one 8N1 UART frame (start=0, 8 data LSB-first, stop=1) out on P3.0 at
 * a configurable baud, synchronized to CPU clocks (bit_clocks = xtal / baud;
 * tick() gets machine cycles, scaled by clock_per_cycle()==12). It does NOT
 * feed SBUF — that is the core UART's role once the firmware has configured the
 * receiver. See rxd.cc and simulator/issues/003-* for the full rationale.
 */

#ifndef RXD_HEADER
#define RXD_HEADER

#include "stypes.h"
#include "uccl.h"
#include "hwcl.h"
#include "newcmdcl.h"

class cl_rxd: public cl_hw
{
public:
  class cl_memory_cell *cell_p3;     // P3 byte cell (0xB0)
  class cl_memory_cell *cell_bit0;   // bits-space cell for P3.0 (0xB0)
  int   cyc_per_bit;                 // bit time in MACHINE cycles (xtal/baud/12)
  int   frame_bits;                  // total bits in the current frame (10 for 8N1)
  int   cur_bit;                     // index of bit currently on the line; -1 = idle
  long  cyc_acc;                     // accumulated machine cycles toward the next bit
  t_mem frame;                       // the framed bit pattern (bit0=start .. bit9=stop)
public:
  cl_rxd(class cl_uc *auc);
  virtual int init(void);

  virtual int tick(int cycles);
  virtual bool set_cmd(class cl_cmdline *cmdline, class cl_console_base *con);
  virtual void print_info(class cl_console_base *con);

  void drive(int level);
  void queue_byte(u8_t b);
};

#endif

/* End of rxdcl.h */
