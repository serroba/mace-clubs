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
    compareWithBaseline,
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
    freeAtReady: 7464,
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
    it("fails a device that never reported", () => {
        // The Instinct 2's actual failure. No number comes back at all,
        // which must not read as "no problem found".
        assert.equal(isCritical(reading({ freeAtReady: null })), true);
    });

    it("fails a device that crashed", () => {
        assert.equal(isCritical(reading({ failure: "ran out of memory before its first screen" })), true);
    });

    it("fails a device down to its last few KB", () => {
        assert.equal(isCritical(reading({ freeAtReady: CRITICAL_FREE_BYTES - 1 })), true);
    });

    it("passes the Instinct 2 as it ships today", () => {
        // 7,464 bytes, and it runs a full workout there. The floor has to sit
        // below what works, or the gate is red on main and nobody keeps it.
        assert.equal(isCritical(reading()), false);
        assert.equal(isTight(reading()), true);
    });

    it("says nothing about a device with room", () => {
        const roomy = reading({ device: "fenix7", freeAtReady: 710056, totalMemory: 782336 });
        assert.equal(isCritical(roomy), false);
        assert.equal(isTight(roomy), false);
    });
});

void describe("baselines", () => {
    it("reports a drop the size of the one that broke the Instinct 2", () => {
        // v0.13.4 cost about 2.6KB and shipped. On a pull request this now
        // says so.
        assert.equal(isNotableDrop(reading({ freeAtReady: 7464 }), 7464 + NOTABLE_DROP_BYTES), true);
        assert.match(compareWithBaseline(reading({ freeAtReady: 7464 }), 10_000) ?? "", /2536 bytes less than recorded/);
    });

    it("stays quiet about noise", () => {
        assert.equal(compareWithBaseline(reading({ freeAtReady: 7464 }), 7500), null);
        assert.equal(isNotableDrop(reading({ freeAtReady: 7464 }), 7500), false);
    });

    it("says nothing about a device with no baseline yet", () => {
        assert.equal(compareWithBaseline(reading(), undefined), null);
        assert.equal(isNotableDrop(reading(), undefined), false);
    });

    it("welcomes headroom going the other way", () => {
        assert.match(compareWithBaseline(reading({ freeAtReady: 9000 }), 7464) ?? "", /1536 bytes more than recorded/);
        assert.equal(isNotableDrop(reading({ freeAtReady: 9000 }), 7464), false);
    });
});

void describe("describe", () => {
    it("leads with the failure when there is one", () => {
        assert.match(describeReading(reading({ failure: "did not build" })), /did not build/);
    });

    it("says the app never got there, rather than printing a zero", () => {
        assert.match(describeReading(reading({ freeAtReady: null })), /did not reach its first screen/);
    });

    it("gives the number against the device's own total", () => {
        assert.match(describeReading(reading()), /7KB free of 92KB/);
    });
});
