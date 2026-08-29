---
description: Launch, drive, and screenshot the mace-clubs Connect IQ app in the macOS Garmin simulator - covers manual exploration and the automated e2e framework in tools/e2e/.
---

# Running mace-clubs in the Connect IQ simulator (macOS)

There is no official automation API for the Connect IQ simulator. Everything
below was found empirically (see `tools/e2e/simulator.ts`'s header comment
for the canonical version) and is wrapped in a reusable driver - **prefer
using `tools/e2e/simulator.ts`'s `Simulator` class over redoing this by
hand**; see `docs/e2e-testing.md` for the full BDD test-writing guide.

## Prerequisites

The calling terminal/app needs **Screen Recording** and **Accessibility**
permission (System Settings > Privacy & Security). Without Screen Recording,
`screencapture` silently returns an all-black image - that's the tell.

## Quick manual drive (no test framework)

```sh
cd /Users/sebastian/projects/mace-clubs
make build   # produces bin/mace-clubs.prg
```

```ts
// scratch.ts, run with: node --experimental-strip-types scratch.ts
import { Simulator } from "./tools/e2e/simulator.ts";

const sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
console.log(await sim.readText());       // OCR the current screen
await sim.press("select");               // "select" | "back" | "up" | "down"
await sim.hold("menu");                  // long-press (MENU has no its own key code)
const png = await sim.screenshot();      // Buffer, 176x176, watch screen only
sim.close();
```

## The mechanics (why the driver looks the way it does)

- **Focus**: `set frontmost to true` alone does NOT give the simulator real
  key-event focus. You must also `click window 1` (its title bar) via
  System Events before sending any key code, every time.
- **Buttons -> macOS key codes**: SELECT=Return(`36`), BACK=Escape(`53`),
  UP=`126`, DOWN=`125`. MENU is a **long-press of UP** (`key down`/`key up`
  with a delay between) - confirmed via this device's own
  `~/Library/Application Support/Garmin/ConnectIQ/Devices/<device>/simulator.json`,
  whose `keys` array has `{"behavior":"onMenu","id":"menu","isHold":true}`
  at the same `location` as `"up"`.
- **Window is resizable**: a previous session (or a stray drag) can leave
  the window at any size. Force it back with `set size of window 1 to
  {381, 552}` before computing any screen-region math from it.
- **Screen region within the window**: `simulator.json`'s
  `display.location` gives `{x:101, y:158, width:176, height:176}` in the
  device image's own coordinate space, which sits **28pt below the
  window's top-left** (a standard macOS title bar) at **1:1 scale** (no
  DPI scaling relative to the window's reported point size - only the
  *captured PNG* is 2x on a Retina display, which matters if you post-process
  it directly rather than through `Simulator.screenshot()`).
- **`monkeydo` can silently fail to connect** if the simulator hasn't
  finished booting - it prints `Unable to connect` rather than erroring.
  Retry (see `tools/visual_check.sh`'s `visual_check.sh` and
  `Simulator.loadApp()`'s identical pattern) rather than assuming one
  attempt succeeded.
- **Always launch a fresh simulator process per test file/session** rather
  than trying to reuse one and reset the loaded app's state (e.g. via
  "File > Kill App") - that was tried and was not reliable enough in
  practice (see `Simulator.launch()`'s doc comment).
- **OCR** (`tools/e2e/ocr.swift`, driven by `Simulator.readText()`) uses
  macOS's built-in Vision framework via a `swift` one-off script - no extra
  dependency to install, ~0.5-1s per call once warmed up. Prefer it over a
  screenshot diff for asserting *what state the app is in*.

## Known flakiness

A cold launch can take 10-30s; under system memory pressure (check `top` /
`memory_pressure` if launches start timing out) a JVM-backed app like this
simulator can be **much** slower or appear to hang entirely from GC
thrashing - that's not necessarily a driver regression. `pkill -9 -f
"ConnectIQ.app/Contents/MacOS/simulator"` and retry once memory frees up.
