/*
 * ucsim ADC0808/0809 peripheral for the ROB3 board
 *
 * WHY THIS EXISTS
 * ---------------
 * Stock ucSim models the MCS-51 core only. The ROB3 firmware's initialization
 * and its whole axis-servo subsystem depend on the external ADC that reads the
 * six axis feedback pots:
 *
 *   - Init blocks at 0x0680 (JB/JNB 0x22.0) waiting for the axis-servo ISR,
 *     which only runs when the ADC asserts EOC -> INT1.
 *   - The servo ISR (EXT1, 0x00C0) reads a feedback byte with MOVX from the
 *     ADC window and cycles the six channels round-robin.
 *
 * With no ADC model, the ROM stalls forever, so the existing sim_run.sh test
 * has to hand-inject IRAM 0x22 to fake the EOC. This module replaces that
 * scaffolding with a real device so the ROM can free-run from `reset; run`.
 *
 * HARDWARE MODELLED (verified landmarks — see rob3-firmware-sim / rob3-hardware)
 * -----------------------------------------------------------------------------
 *   [HW]  ADC0808/0809, 8 channels, EOC wired to 8031 INT1 (pin 13).
 *   [BYTE] Firmware selects a channel by writing the ADC window at DPH=0x58
 *          (channel line A8=0) and reads feedback at DPH=0x58/0x59. On this
 *          board those MOVX windows are XRAM 0x5800 (A8=0) and 0x5900 (A8=1).
 *   [SIM]  The servo ISR feedback-store path (0x00D5) does
 *          MOV DPH,#0x59 / MOVX A,@DPTR / MOV @R1,A  -> reads XRAM 0x5900.
 *   [BYTE] The round-robin ISR tail (0x0278) writes the next channel
 *          (R0+1)&7 to the ADC window, i.e. to XRAM 0x5800.
 *
 * BEHAVIORAL CONTRACT
 * -------------------
 *   write(0x5800): latch channel = value & 0x07, and START a conversion
 *                  (arm an EOC countdown of `conv_delay` cycles).
 *   read (0x5800 / 0x5900): return feedback[channel] (the modelled pot).
 *   tick(): when the conversion countdown reaches 0, (optionally) integrate
 *           the modelled arm from the L293 motor bits, then assert EOC by
 *           setting TCON.IE1 (0x08). The 8051 core's external-#1 interrupt
 *           source reads that flag and vectors to 0x0013 -> 0x00C0 whenever
 *           EA+EX1 are enabled -- exactly the real EOC->INT1 path.
 *
 * This is the natural trigger the firmware is written around: one conversion
 * per channel select, one servo-ISR invocation per EOC, six axes cycled.
 *
 * COMMANDS
 * --------
 *   set hardware adc <ch> <value>   force feedback[ch] = value (0..255)
 *   set hardware adc <0|1>          disable/enable the L293->arm integrator
 *   set hardware adc                 (no args) print state
 *
 * This is a compile-time ucsim module; register it in cl_51core::mk_hw_elements().
 */

#include <stdio.h>
#include "argcl.h"
#include "regs51.h"
#include "types51.h"
#include "adccl.h"

/* TCON bit for external interrupt 1 request (EOC -> INT1). regs51.h: bmIE1 */
#ifndef bmIE1
#define bmIE1 0x08
#endif

/* A conversion on an ADC0808 at ~640 kHz clock takes ~100 us; the exact figure
 * does not matter for functional simulation. Pick a small cycle count so the
 * ISR fires promptly after each channel select but not on the very same
 * instruction (mirrors real hardware latency). */
#define ADC_DEFAULT_CONV_DELAY 64

cl_adc::cl_adc(class cl_uc *auc):
  cl_hw(auc, HW_PORT, 0, "adc")
{
  int i;
  for (i= 0; i < ROB3_ADC_NCH; i++)
    feedback[i]= 0x80;          /* mid-scale until the caller seeds a value */
  channel= 0;
  conv_delay= ADC_DEFAULT_CONV_DELAY;
  conv_countdown= -1;           /* idle: no conversion in flight */
  closed_loop= false;
  cell_adc_lo= 0;
  cell_adc_hi= 0;
  cell_porta= 0;
  cell_portc= 0;
  cell_tcon= 0;
}

int
cl_adc::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  class cl_address_space *xram= uc->address_space(MEM_XRAM_ID);
  if (xram)
    {
      cell_adc_lo= register_cell(xram, 0x5800);
      cell_adc_hi= register_cell(xram, 0x5900);
      cell_porta = register_cell(xram, 0x5000);
      cell_portc = register_cell(xram, 0x5200);
    }
  if (sfr)
    cell_tcon= register_cell(sfr, TCON);   /* TCON = 0x88 */
  return 0;
}

/* Begin a conversion on channel ch: latch it and arm the EOC countdown. */
void
cl_adc::start_conversion(int ch)
{
  channel= ch & 0x07;
  conv_countdown= conv_delay;
}

/* Optional closed loop: nudge the selected axis' modelled pot toward wherever
 * the firmware is driving the corresponding L293. The exact per-axis bit
 * mapping in 8255 Port A / Port C is [INFER] (see hardware/motors), so this is
 * deliberately a coarse, clearly-labelled model: if any drive bit for the axis
 * is set we step the feedback by 1 in the commanded direction. Callers who need
 * a faithful arm must finish the servo/L293 reverse-engineering first; this is
 * enough to demonstrate the loop closing, not to certify servo dynamics. */
void
cl_adc::integrate_arm(void)
{
  if (!closed_loop)
    return;
  if (channel < 0 || channel >= 6)
    return;

  t_mem porta= cell_porta ? cell_porta->get() : 0;
  t_mem portc= cell_portc ? cell_portc->get() : 0;

  /* [INFER] axes 0..3 on Port A (two bits/axis), axes 4..5 on Port C. */
  t_mem bits;
  int shift;
  if (channel < 4) { bits= porta; shift= channel * 2; }
  else             { bits= portc; shift= (channel - 4) * 2; }

  int fwd= (bits >> shift)       & 1;   /* drive-forward bit  [INFER] */
  int rev= (bits >> (shift + 1)) & 1;   /* drive-reverse bit  [INFER] */

  int v= (int)feedback[channel];
  if (fwd && !rev && v < 0xFF) v++;
  else if (rev && !fwd && v > 0x00) v--;
  feedback[channel]= (t_mem)v;
}

t_mem
cl_adc::read(class cl_memory_cell *cell)
{
  /* Either ADC window returns the currently selected channel's pot value. */
  if (cell == cell_adc_lo || cell == cell_adc_hi)
    return feedback[channel & 0x07];
  return cell->get();
}

void
cl_adc::write(class cl_memory_cell *cell, t_mem *val)
{
  if (cell == cell_adc_lo)
    {
      /* Writing the ADC window selects a channel and starts a conversion. */
      start_conversion(*val & 0x07);
    }
  /* Keep the cell's stored value coherent for dumps / other readers. */
  cell->set(*val);
}

int
cl_adc::tick(int cycles)
{
  if (conv_countdown < 0)
    return resGO;                 /* idle, nothing converting */

  conv_countdown-= cycles;
  if (conv_countdown > 0)
    return resGO;                 /* still converting */

  /* EOC: conversion finished. */
  conv_countdown= -1;
  integrate_arm();                /* update the modelled pot (closed loop) */

  /* Assert EOC -> INT1 by raising the external-#1 request flag in TCON. The
   * core's cl_it_src for "external #1" reads TCON.IE1 and vectors to 0x0013
   * (-> 0x00C0) when EA+EX1 are set. This is the real EOC->INT1 wiring. */
  if (cell_tcon)
    cell_tcon->set(cell_tcon->get() | bmIE1);

  return resGO;
}

/* set hardware adc <ch> <value> | <0|1> | (none) */
bool
cl_adc::set_cmd(class cl_cmdline *cmdline, class cl_console_base *con)
{
  class cl_cmd_arg *params[2] = { cmdline->param(0), cmdline->param(1) };

  /* "set hardware adc <ch> <value>" -> seed a channel's feedback */
  if (cmdline->syntax_match(uc, NUMBER NUMBER))
    {
      int ch= params[0]->value.number & 0x07;
      int v = params[1]->value.number & 0xFF;
      feedback[ch]= (t_mem)v;
      con->dd_printf("adc: channel %d feedback = 0x%02x\n", ch, v);
      return true;
    }

  /* "set hardware adc <0|1>" -> toggle the closed-loop integrator */
  if (cmdline->syntax_match(uc, NUMBER))
    {
      closed_loop= (params[0]->value.number != 0);
      con->dd_printf("adc: closed-loop %s\n", closed_loop ? "ON" : "OFF");
      return true;
    }

  /* no (recognised) args => print state */
  print_info(con);
  return true;
}

void
cl_adc::print_info(class cl_console_base *con)
{
  int i;
  con->dd_printf("%s[%d]\n", id_string, id);
  con->dd_printf("  selected channel: %d   conv_delay: %d cycles   closed-loop: %s\n",
		 channel, conv_delay, closed_loop ? "ON" : "OFF");
  con->dd_printf("  converting: %s\n",
		 (conv_countdown >= 0) ? "yes" : "no");
  con->dd_printf("  feedback[0..7]:");
  for (i= 0; i < ROB3_ADC_NCH; i++)
    con->dd_printf(" %02x", feedback[i]);
  con->dd_printf("\n");
}

/* End of adc.cc */
