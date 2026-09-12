#!/usr/bin/env python3
"""ROB3 Teachbox + arm GUI.

A Tkinter front-end that shows the real ROB3 Teachbox (5x5 key matrix) on the
left and the six robot axes on the right. Pressing keys drives the REAL firmware
running in ucSim; the axis pots are modelled by the external plant (the physics
that is not on the 8031 bus — see ../ARCHITECTURE.md).

Layers (all honest about what is real vs modelled):
  * Keypad     -> `set hardware teachbox <row> <group>` into the firmware
                  scanner (cl_teachbox module), when available.
  * Firmware   -> the actual ROM in ucSim (cl_adc gives it a live ADC).
  * Plant      -> motor->pot integration in Python (plant.py). [INFER] direction.

Run:
    UCSIM_51=/path/to/ucsim_51 python3 gui.py
Falls back to a plant-only demo if the custom ucsim_51 (with the cl_hw modules)
is not found — the keypad then drives the plant directly so the UI still works.

No third-party dependencies (Tkinter ships with CPython).
"""
from __future__ import annotations
import queue
import threading
import tkinter as tk
from tkinter import ttk

from plant import Plant, N_AXES
try:
    from engine import UCSimEngine, MAIN_LOOP, IRAM_CURPOS
    HAVE_ENGINE = True
except Exception:                       # pragma: no cover - engine optional
    HAVE_ENGINE = False

# ---- Teachbox 5x5 layout -----------------------------------------------------
# Physical panel (README/board.md). Each cell maps to the firmware (row, group)
# used by the keypad scanner. group 1/2/3 = P1.5/6/7; row = 74LS138 /Y0../Y7.
# Verified key->(row,group) from hardware/teachbox/test.md processKeyPress().
#
# We arrange the 25 keys in the documented 5x5 grid; the (row,group) each maps
# to is annotated so the firmware sees the correct strobe/column.
KEYS = [
    # label,  row, group,  kind
    ("RUN",   7, 3, "sys"), ("STOP", 0, 0, "stop"), ("INS", 0, 3, "sys"),
    ("DEL",   7, 1, "cmd"), ("ERR",  6, 1, "cmd"),

    ("POS",   2, 3, "sys"), ("TIM",  3, 3, "sys"), ("OUT", 1, 3, "sys"),
    ("MARK",  4, 3, "sys"), ("GOTO", 5, 3, "sys"),

    ("IF",    6, 3, "sys"), ("NOP",  2, 1, "cmd"), ("ENT", 5, 1, "ent"),
    ("↑/→",   3, 1, "jog"), ("↓/←",  4, 1, "jog"),

    ("7",     7, 2, "num"), ("8",    0, 1, "num"), ("9",  1, 1, "num"),
    ("4",     4, 2, "num"), ("5",    5, 2, "num"),

    ("6",     6, 2, "num"), ("1",    1, 2, "num"), ("2",  2, 2, "num"),
    ("3",     3, 2, "num"), ("0",    0, 2, "num"),
]

# Axis display metadata (README axis table). angle span for the 0..255 code.
AXES = [
    ("q1 Base",     "-80..+80 deg"),
    ("q2 Shoulder", "-30..+70 deg"),
    ("q3 Elbow",    "-100..0 deg"),
    ("q4 Wrist",    "-100..+100 deg"),
    ("q5 Roll",     "-100..+100 deg"),
    ("Gripper",     "0..60 mm"),
]

KIND_COLOR = {
    "num": "#2d3f5f", "cmd": "#5a3d2b", "sys": "#2b4a3a",
    "jog": "#5f4a2d", "ent": "#2b5f3f", "stop": "#6b2b2b",
}


class Rob3GUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title("ROB3 Teachbox + Arm — ucSim")
        root.configure(bg="#1e1e28")

        self.plant = Plant(pot=[128] * N_AXES, step=6)
        self.selected_axis: int | None = None
        self.engine = None
        self.q: "queue.Queue[tuple]" = queue.Queue()
        self.log_lines: list[str] = []
        self._push_busy = False
        self._last_pushed = [-1] * N_AXES

        self._build_keypad()
        self._build_axes()
        self._build_status()

        # start engine in a worker thread (it can take a couple seconds to boot)
        threading.Thread(target=self._boot_engine, daemon=True).start()
        self.root.after(50, self._pump)
        self.root.after(120, self._tick)

    # -- UI construction ------------------------------------------------------
    def _build_keypad(self):
        frame = tk.LabelFrame(self.root, text="Teachbox (5x5)", fg="#cdd",
                              bg="#1e1e28", font=("TkDefaultFont", 10, "bold"))
        frame.grid(row=0, column=0, padx=10, pady=10, sticky="n")
        for i, (label, r, g, kind) in enumerate(KEYS):
            row, col = divmod(i, 5)
            b = tk.Button(frame, text=label, width=6, height=2,
                          bg=KIND_COLOR.get(kind, "#333"), fg="#eee",
                          activebackground="#888", relief="raised",
                          command=lambda L=label, R=r, G=g, K=kind:
                              self.on_key(L, R, G, K))
            b.grid(row=row, column=col, padx=3, pady=3)

    def _build_axes(self):
        frame = tk.LabelFrame(self.root, text="Axes — pot feedback (0..255)",
                              fg="#cdd", bg="#1e1e28",
                              font=("TkDefaultFont", 10, "bold"))
        frame.grid(row=0, column=1, padx=10, pady=10, sticky="n")
        self.axis_widgets = []
        for a, (name, span) in enumerate(AXES):
            tk.Label(frame, text=f"{a}  {name}", width=14, anchor="w",
                     fg="#ddd", bg="#1e1e28").grid(row=a, column=0, sticky="w")
            canvas = tk.Canvas(frame, width=260, height=22, bg="#0f0f16",
                               highlightthickness=1, highlightbackground="#333")
            canvas.grid(row=a, column=1, padx=6, pady=4)
            target_lbl = tk.Label(frame, text="", width=10, fg="#8ab",
                                  bg="#1e1e28")
            target_lbl.grid(row=a, column=2)
            tk.Label(frame, text=span, width=13, anchor="w", fg="#777",
                     bg="#1e1e28").grid(row=a, column=3, sticky="w")
            self.axis_widgets.append((canvas, target_lbl))

    def _build_status(self):
        bar = tk.Frame(self.root, bg="#12121a")
        bar.grid(row=1, column=0, columnspan=2, sticky="we", padx=10, pady=(0, 8))
        self.status = tk.Label(bar, text="booting ucSim...", anchor="w",
                               fg="#9c9", bg="#12121a")
        self.status.pack(side="left")
        self.sel = tk.Label(bar, text="axis: none", anchor="e",
                            fg="#cc9", bg="#12121a")
        self.sel.pack(side="right")

        logf = tk.LabelFrame(self.root, text="Log", fg="#cdd", bg="#1e1e28")
        logf.grid(row=2, column=0, columnspan=2, sticky="we", padx=10, pady=(0, 10))
        self.logbox = tk.Text(logf, height=6, width=78, bg="#0f0f16",
                              fg="#9c9", insertbackground="#9c9")
        self.logbox.pack(fill="both", expand=True)

    # -- engine boot (worker thread) ------------------------------------------
    def _boot_engine(self):
        if not HAVE_ENGINE:
            self.q.put(("status", "engine module unavailable — plant-only demo"))
            return
        try:
            eng = UCSimEngine()
            if eng.has_modules:
                eng.reset()
                reached = eng.run_to(MAIN_LOOP)
                self.engine = eng
                self.q.put(("status",
                            f"ucSim up [modules]  main-loop={'ok' if reached else 'n/a'}"))
                pos = eng.read_positions()
                self.q.put(("seed", pos))
            else:
                # stock s51: no cl_hw modules -> don't run the ROM (avoids the
                # serial auto-detect hang). Plant-only demo; keypad drives plant.
                eng.close()
                self.q.put(("status", "stock s51 (no cl_hw modules) — plant-only demo"))
        except Exception as e:                      # pragma: no cover
            self.q.put(("status", f"engine failed: {e} — plant-only demo"))

    # -- key handling ---------------------------------------------------------
    def on_key(self, label: str, row: int, group: int, kind: str):
        self.log(f"key {label}  (row {row}, group {group})")
        # Numeric axis-select convention (POSITION mode): key index N -> axis N-2.
        if kind == "num" and label.isdigit():
            n = int(label)
            if 2 <= n <= 7:
                self.selected_axis = n - 2
                self.sel.config(text=f"axis: {self.selected_axis}")
        elif kind == "jog" and self.selected_axis is not None:
            # ↑/→ = increase pot, ↓/← = decrease (drive the plant target)
            step = self.plant.step if "↑" in label else -self.plant.step
            self._nudge_target(self.selected_axis, step)
        # push the key into the real firmware scanner if the module is present
        if self.engine and self.engine.has_modules and group in (1, 2, 3):
            threading.Thread(target=self._press_worker, args=(row, group),
                             daemon=True).start()

    def _press_worker(self, row: int, group: int):
        try:
            self.engine.press(row, group)
            # keypad scan is quick; keep the cycle budget small so the UI stays
            # responsive (interactive ucSim over a pty is slow per cycle).
            self.engine.run_cycles(20000)
            self.engine.release()
        except Exception as e:                      # pragma: no cover
            self.q.put(("status", f"press error: {e}"))

    def _nudge_target(self, axis: int, delta: int):
        cur = getattr(self, "_targets", None)
        if cur is None:
            self._targets = list(self.plant.pot)
        self._targets[axis] = max(0, min(255, self._targets[axis] + delta))

    # -- periodic update ------------------------------------------------------
    def _tick(self):
        # advance the plant toward per-axis targets (the "physics") — fast, local
        if not hasattr(self, "_targets"):
            self._targets = list(self.plant.pot)
        for a in range(N_AXES):
            self.plant.move_toward(a, self._targets[a])
        self._redraw()
        # push pot values back into the firmware's ADC in the background, and
        # only the ones that changed, so the pty I/O never stalls the UI.
        if self.engine and self.engine.has_modules and not self._push_busy:
            changed = [(a, self.plant.pot[a]) for a in range(N_AXES)
                       if self.plant.pot[a] != self._last_pushed[a]]
            if changed:
                self._push_busy = True
                threading.Thread(target=self._push_worker, args=(changed,),
                                 daemon=True).start()
        self.root.after(120, self._tick)

    def _push_worker(self, changed):
        try:
            for a, v in changed:
                self.engine.push_pot(a, v)
                self._last_pushed[a] = v
        except Exception:
            pass
        finally:
            self._push_busy = False

    def _redraw(self):
        for a, (canvas, tlabel) in enumerate(self.axis_widgets):
            canvas.delete("all")
            w = 260
            val = self.plant.pot[a]
            x = int(w * val / 255)
            canvas.create_rectangle(0, 0, x, 22, fill="#3a7", width=0)
            canvas.create_text(w - 24, 11, text=f"{val:3d}", fill="#cff")
            tgt = getattr(self, "_targets", self.plant.pot)[a]
            tx = int(w * tgt / 255)
            canvas.create_line(tx, 0, tx, 22, fill="#f94", width=2)
            tlabel.config(text=f"tgt {tgt:3d}")

    def _pump(self):
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "status":
                    self.status.config(text=payload)
                    self.log(payload)
                elif kind == "seed":
                    if all(v >= 0 for v in payload):
                        self.plant.pot = list(payload)
                        self._targets = list(payload)
        except queue.Empty:
            pass
        self.root.after(50, self._pump)

    def log(self, msg: str):
        self.log_lines.append(msg)
        self.log_lines = self.log_lines[-200:]
        if hasattr(self, "logbox"):
            self.logbox.delete("1.0", "end")
            self.logbox.insert("end", "\n".join(self.log_lines[-12:]))
            self.logbox.see("end")

    def on_close(self):
        if self.engine:
            try:
                self.engine.close()
            except Exception:
                pass
        self.root.destroy()


def main():
    root = tk.Tk()
    app = Rob3GUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
