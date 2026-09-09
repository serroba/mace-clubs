// The memory check's pure parts. Measuring a device needs a simulator and is
// exercised by `make memory-headroom`; everything asserted here is a function
// over what that measurement returned.
//
// Worth testing because of what the check is for. The app grew past the
// Instinct 2's 96KB in v0.13.4 and crashed inside getInitialView() before
// drawing a frame - on 11.94% of installs, through a green pipeline, until a
// 1-star review said so four months later. A check that silently reports
// "fine" would be worse than no check, because it would be believed.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
    atRiskSelection,
    couldNotMeasure,
    AT_RISK_LIMIT_BYTES,
    compareWithBaseline,
    headroom,
    notableDropBytes,
    CRITICAL_FREE_BYTES,
    describe as describeReading,
    isCritical,
    isNotableDrop,
    isTight,
    NOTABLE_DROP_BYTES,
    parseProbe,
    type Reading,
} from "./memory-headroom.ts";

const reading = (over: Partial<Reading> = {}): Reading => ({
    device: "instinct2",
    freeAtReady: 7296,
    freeAtPeak: 2016,
    totalMemory: 94024,
    failure: null,
    ...over,
});

void describe("parseProbe", () => {
    it("reads the line the app prints", () => {
        const output = "MEMPROBE ready total=94024 used=86800 free=7224\n";
        assert.deepEqual(parseProbe(output, "ready"), { total: 94024, used: 86800, free: 7224 });
    });

    it("tells the two stages apart", () => {
        const output = ["MEMPROBE entry total=94024 used=80280 free=13744", "MEMPROBE ready total=94024 used=86800 free=7224"].join(
            "\n",
        );
        assert.equal(parseProbe(output, "entry")?.free, 13744);
        assert.equal(parseProbe(output, "ready")?.free, 7224);
    });

    it("returns null when the app never got that far", () => {
        // What an Out Of Memory crash actually leaves behind: the entry line
        // and nothing after it.
        assert.equal(parseProbe("MEMPROBE entry total=94024 used=90400 free=3624\n", "ready"), null);
        assert.equal(parseProbe("", "ready"), null);
    });
});

void describe("verdicts", () => {
    it("judges on the peak, not the first screen", () => {
        // The whole point of the peak stage. 7,296 bytes at the first
        // screen looks comfortable; the settings menu built on top of it
        // leaves 2,064, and that is the number that decides.
        assert.equal(headroom(reading()), 2016);
        assert.equal(headroom(reading({ freeAtPeak: null })), 7296);
    });

    it("fails a device that never reported", () => {
        // The Instinct 2's actual failure. No number comes back at all,
        // which must not read as "no problem found".
        assert.equal(isCritical(reading({ freeAtReady: null, freeAtPeak: null })), true);
    });

    it("does not call an unreachable simulator a device that cannot hold the app", () => {
        // The first nightly over all 120 devices reported five watches as
        // "cannot hold the app" when the simulator had died ten devices
        // earlier. Wrong verdict, and the most damaging kind: it accuses the
        // product of the tool's own failure.
        const lost = reading({ freeAtReady: null, freeAtPeak: null, failure: "the simulator was not reachable" });
        assert.equal(couldNotMeasure(lost), true);
        assert.equal(isCritical(lost), false);
    });

    it("still refuses to call an unmeasured device fine", () => {
        // Both verdicts fail the run. The difference is what it says, not
        // whether it goes red.
        const lost = reading({ freeAtReady: null, freeAtPeak: null, failure: "did not build\nsomething" });
        assert.equal(couldNotMeasure(lost), true);
    });

    it("fails a device that crashed", () => {
        // Out of memory is a real verdict about the device, not a failed
        // measurement, so it stays critical.
        const oom = reading({ failure: "ran out of memory before its first screen" });
        assert.equal(couldNotMeasure(oom), false);
        assert.equal(isCritical(oom), true);
    });

    it("fails a device down to its last few hundred bytes", () => {
        assert.equal(isCritical(reading({ freeAtPeak: CRITICAL_FREE_BYTES - 1 })), true);
        // And is not fooled by a comfortable first screen above it.
        assert.equal(isCritical(reading({ freeAtReady: 30_000, freeAtPeak: CRITICAL_FREE_BYTES - 1 })), true);
    });

    it("passes the Instinct 2 as it ships today", () => {
        // 2,064 bytes with the settings menu up, and it runs a full workout
        // there. The floor has to sit below what works, or the gate is red
        // on main and nobody keeps it.
        assert.equal(isCritical(reading()), false);
        assert.equal(isTight(reading()), true);
    });

    it("says nothing about a device with room", () => {
        const roomy = reading({ device: "fenix7", freeAtReady: 710056, freeAtPeak: 700000, totalMemory: 782336 });
        assert.equal(isCritical(roomy), false);
        assert.equal(isTight(roomy), false);
    });
});

void describe("baselines", () => {
    it("scales the threshold to what the device actually has", () => {
        // A flat 2KB cannot fire on a watch with 2,064 bytes left - it would
        // be dead before the check spoke. Ten percent of the real figure
        // asks the same question at the right scale.
        assert.equal(notableDropBytes(2064), 206);
        assert.equal(notableDropBytes(29_000), NOTABLE_DROP_BYTES);
    });

    it("reports a drop against the peak", () => {
        assert.equal(isNotableDrop(reading({ freeAtPeak: 1800 }), 2064), true);
        assert.match(compareWithBaseline(reading({ freeAtPeak: 1800 }), 2064) ?? "", /264 bytes less than recorded/);
    });

    it("stays quiet about noise", () => {
        // The same build measured four times running gave the same number to
        // the byte, so this floor is well clear of the simulator's own noise.
        assert.equal(compareWithBaseline(reading({ freeAtPeak: 2100 }), 2064), null);
        assert.equal(isNotableDrop(reading({ freeAtPeak: 2100 }), 2064), false);
    });

    it("says nothing about a device with no baseline yet", () => {
        assert.equal(compareWithBaseline(reading(), undefined), null);
        assert.equal(isNotableDrop(reading(), undefined), false);
    });

    it("welcomes headroom going the other way", () => {
        assert.match(compareWithBaseline(reading({ freeAtPeak: 3000 }), 2064) ?? "", /936 bytes more than recorded/);
        assert.equal(isNotableDrop(reading({ freeAtPeak: 3000 }), 2064), false);
    });
});

void describe("describe", () => {
    it("leads with the failure when there is one", () => {
        assert.match(describeReading(reading({ failure: "did not build" })), /did not build/);
    });

    it("says the app never got there, rather than printing a zero", () => {
        assert.match(describeReading(reading({ freeAtReady: null, freeAtPeak: null })), /did not reach its first screen/);
    });

    it("gives the number against the device's own total", () => {
        assert.match(describeReading(reading()), /7KB free of 92KB/);
    });

    it("says what the settings menu costs, in bytes", () => {
        // KB would round 2,016 and 2,800 to the same "2KB", and the whole
        // margin on these watches lives inside that rounding.
        assert.match(describeReading(reading()), /2016 bytes with the settings menu on top/);
    });
});

void describe("atRiskSelection", () => {
    it("says how many devices it could actually read, not just which it picked", () => {
        // The reason this is reported at all: an SDK with one device
        // installed silently selects that one device, and every message
        // after it reads as though the whole tier was covered.
        const selection = atRiskSelection(AT_RISK_LIMIT_BYTES, "/nonexistent");
        assert.equal(selection.devices.length, 0);
        assert.equal(selection.checked, 0);
        assert.ok(selection.total > 100, "the manifest should still list every device");
    });
});
