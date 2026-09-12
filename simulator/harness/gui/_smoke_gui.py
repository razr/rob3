#!/usr/bin/env python3
"""Headless smoke test for the GUI stack (engine + plant + Tk under Xvfb).

Boots the GUI, simulates: select axis 1 (key '3'), jog up a few times, let the
plant converge and push pots into the firmware, then closes. Asserts the pot
actually moved. Run under xvfb-run.
"""
import os, sys, time
import tkinter as tk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gui as guimod


def main():
    root = tk.Tk()
    app = guimod.Rob3GUI(root)

    # give the engine a moment to boot
    def scenario():
        app.on_key("3", 3, 2, "num")       # select axis 1
        for _ in range(6):
            app.on_key("↑/→", 3, 1, "jog") # jog up
        # let plant converge (fast, local) and the UI redraw
        root.after(2000, finish)

    def finish():
        pot1 = app.plant.pot[1]
        tgt1 = app._targets[1]
        print(f"axis1 target={tgt1} pot={pot1}", flush=True)
        print(f"engine={'up' if app.engine else 'none'} "
              f"modules={getattr(app.engine,'has_modules',False)}", flush=True)
        ok = tgt1 > 128 and pot1 == tgt1
        print("SMOKE OK" if ok else "SMOKE FAIL", flush=True)
        app.on_close()
        root.quit()
        os._exit(0 if ok else 1)

    # scenario runs regardless of engine state (plant is the interactive core)
    root.after(1500, scenario)
    root.mainloop()


if __name__ == "__main__":
    main()
