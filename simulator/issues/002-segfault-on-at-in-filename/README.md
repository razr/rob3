# Segfault while loading an input file whose name contains `@`

**Component:** file loader (`core/sim.src/uc.cc`, `cl_uc::read_file`)
**Version:** ucSim 0.9.9 (`s51` / `ucsim_51`)
**Severity:** high — crash (NULL deref) on a legitimate-looking filename
**Status:** **submitted upstream and closed** — <https://github.com/danieldrotos/ucsim/issues/13>

## Summary

`s51 file@name.hex` **segfaults** instead of reporting an error. The `@` is
parsed as a `filename@memoryspace` selector (so `FN1@FN2.HEX` is read as file
`FN1` into a memory space named `FN2.HEX`), that memory space does not exist,
and the error path calls `con->dd_printf()` where `con` is **NULL** — the
command-line input-file path loads files with `con == NULL`.

## Root cause

In `cl_uc::read_file` (`src/core/sim.src/uc.cc`), the "memory can not be found"
branch unconditionally dereferences `con`:

```c
if (is.get_mem() == NULL)
  {
    con->dd_printf("Memory %s can not be found\n",   // con == NULL here
                   is.get_mem_name()->cstr());
    return 0;
  }
```

When called from the command-line input-file path, `con` is NULL, so this
crashes.

## Fix

Guard the NULL console and fall back to `stderr`:

```c
if (is.get_mem() == NULL)
  {
    const char *mn = is.get_mem_name()->cstr();
    if (con)
      con->dd_printf("Memory %s can not be found\n", mn);
    else
      fprintf(stderr, "Memory %s can not be found\n", mn);
    return 0;
  }
```

## Notes

Submitted upstream as issue #13 and closed. Some checkouts already carry this
guard; verify against your tree before applying.
