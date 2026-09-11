/*
 * ucsim teachbox peripheral for the ROB3 board
 *
 * Models the ROB3 Teachbox: a 5x5 key matrix + 8 indicator LEDs on a DB25,
 * scanned by the firmware via a 74LS138 (row strobe driven through the 8255)
 * with the column returns read on Port 1 (P1).
 *
 * How it attaches to the simulated 8051:
 *   - registers the P1 SFR cell: on READ, it returns the SFR value with the
 *     column-group bits (P1.5/6/7) driven for the currently "pressed" key IFF
 *     the strobed matrix row matches that key's row.
 *   - registers the external-data (xdata) cell at 0x5100 (8255 Port B): on
 *     WRITE, it captures the row-strobe value the firmware drives, so the
 *     module knows which matrix row is active when P1 is read.
 *
 * Pressed key is set from the command line:
 *   set hardware teachbox <row> <group>
 *     row   = 0..7 (74LS138 output /Y0../Y7)
 *     group = 1..3 (column group; P1 bit 5/6/7). group 0 = no key pressed.
 *
 * This is a compile-time ucsim module; add it in cl_51core::mk_hw_elements().
 */

#include <stdio.h>
#include "argcl.h"
#include "regs51.h"
#include "types51.h"
#include "teachboxcl.h"

cl_teachbox::cl_teachbox(class cl_uc *auc):
  cl_hw(auc, HW_GPIO, 0, "teachbox")
{
  press_row = -1;     // -1 => no key pressed
  press_group = 0;    // 1..3 => P1 bit 5/6/7
  cur_strobe = 0;     // last row-strobe value seen on 8255 Port B (0x5100)
  cell_p1 = 0;
  cell_pb = 0;
}

int
cl_teachbox::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr = uc->address_space(MEM_SFR_ID);
  class cl_address_space *xram = uc->address_space(MEM_XRAM_ID);
  if (sfr)
    cell_p1 = register_cell(sfr, P1);          // P1 = 0x90
  if (xram)
    cell_pb = register_cell(xram, 0x5100);     // 8255 Port B row strobe
  return 0;
}

// Which matrix row is currently strobed, derived from the row-strobe value.
// The firmware advances the strobe as 0x00,0x10,0x20,... (row = strobe>>4).
int
cl_teachbox::strobed_row(void)
{
  return (cur_strobe >> 4) & 0x07;
}

t_mem
cl_teachbox::read(class cl_memory_cell *cell)
{
  if (cell == cell_p1)
    {
      // The three column-group lines are P1.5/6/7. They idle LOW and go HIGH
      // only for the pressed key on the strobed row. Drive just those bits;
      // leave the lower 5 P1 bits as the cell's own value.
      t_mem v = cell->get() & 0x1f;   // keep P1.0..P1.4, clear the 3 column bits
      if (press_group >= 1 && press_group <= 3 &&
	  press_row == strobed_row())
	{
	  int bit = 4 + press_group;   // group1->bit5, group2->bit6, group3->bit7
	  v |= (1 << bit);
	}
      return v;
    }
  return cell->get();
}

void
cl_teachbox::write(class cl_memory_cell *cell, t_mem *val)
{
  if (cell == cell_pb)
    {
      // Capture the 8255 Port B row strobe the firmware drives.
      cur_strobe = *val & 0xff;
    }
  cell->set(*val);
}

// set hardware teachbox <row> <group>
bool
cl_teachbox::set_cmd(class cl_cmdline *cmdline, class cl_console_base *con)
{
  class cl_cmd_arg *params[2] = { cmdline->param(0), cmdline->param(1) };
  if (cmdline->syntax_match(uc, NUMBER NUMBER))
    {
      press_row = params[0]->value.number & 0x07;
      press_group = params[1]->value.number & 0x0f;
      con->dd_printf("teachbox: pressing row %d, group %d\n",
		     press_row, press_group);
      return true;
    }
  if (cmdline->syntax_match(uc, NUMBER))
    {
      // single arg => release (group 0)
      press_group = 0;
      press_row = -1;
      con->dd_printf("teachbox: released\n");
      return true;
    }
  return false;
}

void
cl_teachbox::print_info(class cl_console_base *con)
{
  con->dd_printf("%s[%d]\n", id_string, id);
  con->dd_printf("  pressed: row=%d group=%d (last strobe=0x%02x, row=%d)\n",
		 press_row, press_group, cur_strobe, strobed_row());
}

/* End of teachbox.cc */
