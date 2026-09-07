// The check that keeps the reduced-build device list honest.
//
// Worth testing on its own because the thing it guards against already
// happened once and reached users: #172 fixed the Out Of Memory crash on the
// Instinct 2 by listing three devices by hand, and two more that share the
// same 96KB ceiling - descentg1 and instinctcrossover - stayed broken in the
// store. A derived list is only an improvement if it actually fails when it
// disagrees with the devices.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
    jungleReducedDevices,
    manifestDevices,
    REDUCED_EXCLUSIONS,
    reducedBuildProblems,
    SMALL_MEMORY_BYTES,
    watchAppMemoryLimit,
} from "./reduced-devices.ts";

const REDUCED_LINE = `$(BASE_EXCLUDES);${REDUCED_EXCLUSIONS.join(";")}`;

function compilerJson(watchAppKb: number): string {
    return JSON.stringify({
        appTypes: [
            { type: "watchFace", memoryLimit: 98304 },
            { type: "watchApp", memoryLimit: watchAppKb * 1024 },
        ],
    });
}

void describe("manifestDevices", () => {
    it("reads the product ids in manifest order", () => {
        const xml = `<iq:products>
            <iq:product id="instinct2"/>
            <iq:product id="fenix7"/>
        </iq:products>`;
        assert.deepEqual(manifestDevices(xml), ["instinct2", "fenix7"]);
    });

    it("finds nothing in a manifest with no products", () => {
        assert.deepEqual(manifestDevices("<iq:manifest></iq:manifest>"), []);
    });
});

void describe("watchAppMemoryLimit", () => {
    it("picks the watchApp limit, not the watch face's", () => {
        assert.equal(watchAppMemoryLimit(compilerJson(96)), 98304);
    });

    it("returns null when the file says nothing useful", () => {
        assert.equal(watchAppMemoryLimit("{}"), null);
        assert.equal(watchAppMemoryLimit(JSON.stringify({ appTypes: [] })), null);
        assert.equal(watchAppMemoryLimit(JSON.stringify({ appTypes: [{ type: "widget", memoryLimit: 65536 }] })), null);
    });
});

void describe("jungleReducedDevices", () => {
    it("maps each device to the annotations it excludes", () => {
        const jungle = [
            "BASE_EXCLUDES = offscreenRender;swingTuning",
            "base.excludeAnnotations = $(BASE_EXCLUDES);noHistory",
            `instinct2.excludeAnnotations = ${REDUCED_LINE}`,
        ].join("\n");
        const found = jungleReducedDevices(jungle);
        // "base" is a jungle keyword, not a device, but it parses the same
        // way - the caller only ever asks about real product ids.
        assert.deepEqual([...(found.get("instinct2") ?? [])].sort(), [...REDUCED_EXCLUSIONS].sort());
    });

    it("ignores comments and unrelated lines", () => {
        assert.equal(jungleReducedDevices("# instinct2.excludeAnnotations = $(BASE_EXCLUDES);history").size, 0);
    });
});

void describe("reducedBuildProblems", () => {
    const wired = new Map([["instinct2", new Set<string>(REDUCED_EXCLUSIONS)]]);

    it("passes when every small device is on the reduced build", () => {
        const limits = new Map([
            ["instinct2", SMALL_MEMORY_BYTES],
            ["fenix7", 768 * 1024],
        ]);
        assert.deepEqual(reducedBuildProblems(["instinct2", "fenix7"], limits, wired), []);
    });

    it("catches the descentg1 case: small, and nobody wired it up", () => {
        const limits = new Map([
            ["instinct2", SMALL_MEMORY_BYTES],
            ["descentg1", SMALL_MEMORY_BYTES],
        ]);
        const problems = reducedBuildProblems(["instinct2", "descentg1"], limits, wired);
        const [problem] = problems;
        assert.ok(problem !== undefined, "expected descentg1 to be reported");
        assert.equal(problems.length, 1);
        assert.equal(problem.device, "descentg1");
        assert.match(problem.detail, /Out Of Memory/);
        // The message has to say what to do, not just that something is wrong.
        assert.match(problem.detail, /excludeAnnotations/);
    });

    it("catches a reduced device that is missing one of the exclusions", () => {
        const partial = new Map([["instinct2", new Set(["history", "swingDebug"])]]);
        const problems = reducedBuildProblems(["instinct2"], new Map([["instinct2", SMALL_MEMORY_BYTES]]), partial);
        const [problem] = problems;
        assert.ok(problem !== undefined, "expected the partial wiring to be reported");
        assert.equal(problems.length, 1);
        assert.match(problem.detail, /motionExport/);
    });

    it("catches a roomy device left on the reduced build", () => {
        // The opposite drift, and the reason the check is not just "is it
        // listed": a device that grows past the ceiling, or was added here by
        // mistake, quietly costs its owners features.
        const limits = new Map([["fenix7", 768 * 1024]]);
        const problems = reducedBuildProblems(["fenix7"], limits, new Map([["fenix7", new Set(["history"])]]));
        const [problem] = problems;
        assert.ok(problem !== undefined, "expected the roomy device to be reported");
        assert.equal(problems.length, 1);
        assert.match(problem.detail, /losing features/);
    });

    it("says nothing about devices whose SDK files are not installed", () => {
        // Locally the SDK usually has a handful of devices; the check should
        // report on those rather than fail because the rest are absent.
        assert.deepEqual(reducedBuildProblems(["fenix7", "venu3"], new Map(), new Map()), []);
    });

    it("treats the threshold as inclusive", () => {
        const atLimit = reducedBuildProblems(["x"], new Map([["x", SMALL_MEMORY_BYTES]]), new Map());
        const justOver = reducedBuildProblems(["x"], new Map([["x", SMALL_MEMORY_BYTES + 1]]), new Map());
        assert.equal(atLimit.length, 1);
        assert.deepEqual(justOver, []);
    });
});
