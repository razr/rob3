/*
 * ucsim ADC0808/0809 peripheral for the ROB3 board (header)
 *
 * Models the 8-channel SAR ADC that reads the six axis feedback pots. Its
 * end-of-conversion (EOC) line is wired to the 8031 INT1 pin, so a finished
 * conversion fires the axis-servo ISR (EXT1 vector 0x0013 -> 0x00C0).
 *
 * SCOPE: this module is a PURE SENSOR + interrupt source. It holds no physics
 * -- just the currently selected channel and a per-channel value cache that is
 * written from OUTSIDE (the plant/harness/bridge). The motor + joint + pot
 * dynamics ("how far the motor moved the axis") live outside ucSim; see
 * ../../harness/ARCHITECTURE.md. cl_adc only serves whatever pot value it was
 * last given and raises EOC -> INT1.
 *
 * See adc.cc for the full behavioral contract.
 */

#ifndef ROB3_ADC_HEADER
#define ROB3_ADC_HEADER

#include "stypes.h"
#include "uccl.h"
#include "hwcl.h"
#include "newcmdcl.h"

#define ROB3_ADC_NCH 8   /* ADC0808/0809: 8 channels (6 axes used) */

class cl_adc: public cl_hw
{
public:
  /* Per-channel pot value cache. NOT physics: this is only what the external
   * plant/harness last wrote for each channel. cl_adc serves it back on a
   * feedback read. Channels 0..5 = the six axes. */
  t_mem pot[ROB3_ADC_NCH];

  int   channel;         /* channel currently selected (last write to 0x5800) */
  int   conv_delay;      /* cycles a conversion takes before EOC              */
  int   conv_countdown;  /* cycles left until EOC; <0 => idle, no conversion  */

  /* registered cells (the two ADC bus windows + TCON for the EOC interrupt) */
  class cl_memory_cell *cell_adc_lo;  /* XRAM 0x5800 (channel sel / A8=0)  */
  class cl_memory_cell *cell_adc_hi;  /* XRAM 0x5900 (feedback / A8=1)     */
  class cl_memory_cell *cell_tcon;    /* SFR  0x88   (TCON; IE1 = EOC->INT1)   */

public:
  cl_adc(class cl_uc *auc);
  virtual int init(void);

  virtual t_mem read(class cl_memory_cell *cell);
  virtual void write(class cl_memory_cell *cell, t_mem *val);
  virtual int tick(int cycles);

  virtual bool set_cmd(class cl_cmdline *cmdline, class cl_console_base *con);
  virtual void print_info(class cl_console_base *con);

private:
  void start_conversion(int ch);
};

#endif

/* End of s51.src/adccl.h */
