/*
 * ucsim teachbox peripheral for the ROB3 board (header)
 */

#ifndef TEACHBOX_HEADER
#define TEACHBOX_HEADER

#include "stypes.h"
#include "uccl.h"
#include "hwcl.h"
#include "newcmdcl.h"

class cl_teachbox: public cl_hw
{
public:
  int press_row;      // 0..7, or -1 if no key pressed
  int press_group;    // 1..3 (P1 bit 5/6/7), 0 = none
  t_mem cur_strobe;   // last 8255 Port B (0x5100) row-strobe value
  class cl_memory_cell *cell_p1;
  class cl_memory_cell *cell_pb;
public:
  cl_teachbox(class cl_uc *auc);
  virtual int init(void);

  virtual t_mem read(class cl_memory_cell *cell);
  virtual void write(class cl_memory_cell *cell, t_mem *val);

  virtual bool set_cmd(class cl_cmdline *cmdline, class cl_console_base *con);
  virtual void print_info(class cl_console_base *con);

  int strobed_row(void);
};

#endif

/* End of s51.src/teachboxcl.h */
