#!/usr/bin/env node
// How much memory the app has left once its first screen exists, per device.
//
// This is the measurement whose absence let the app ship broken. It grew past
// the Instinct 2's 96KB in v0.13.4 and crashed inside getInitialView() before
// drawing a frame - on 11.94% of installs, for four months, through a green
// pipeline and a 1-star review, because nothing in the repo measured this. The
// build sweep proved 120 devices compile; compiling says nothing about whether
// a watch can hold what it compiled.
//
// Reads the MEMPROBE lines that MaceClubsApp prints under the `memoryProbe`
// annotation, which only monkey.probe.jungle compiles in.
//
//     node --experimental-strip-types tools/memory-headroom.ts instinct2 fenix5
//
// Exits non-zero when a device is below MINIMUM_FREE_BYTES, or when the app
// crashed before it could report - which is the failure this exists to catch,
// and reads as "no MEMPROBE line" rather than as a number.

import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { manifestDevices, readMemoryLimits } from "./reduced-devices.ts";
import { resolve as resolveTool } from "./resolve-tool.ts";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Below this, a watch is about to fail the way the Instinct 2 did.
 *
 * Empirical, not aspirational. The build that could not start had 6,216 bytes
 * before constructing its view and needed 5,928 of them, so it died with
 * everything still to do. The build that ships today has 7,224 left *after*
 * the view exists, and passes a full workout on that device - so 7KB is
 * evidently enough in practice and a floor above it would be red on main
 * from the day it landed, which is a gate nobody would keep.
 *
 * This one catches the thing that actually went wrong: a release that eats
 * the last of the headroom on a watch that had little to begin with.
 */
// Measured, not chosen: instinct2 ships today with 2,064 bytes left once the
// settings menu is built, and runs a full workout there. A floor above what
// main actually does is a gate someone deletes in a fortnight.
export const CRITICAL_FREE_BYTES = 1024;

/**
 * Below this, a watch is worth watching but is not failing.
 *
 * Recalibrated for the peak. 12KB was a first-screen figure; against the
 * settings menu every 96KB device is under it, and five devices warning on
 * every run is a warning nobody reads.
 *
 * Reported rather than enforced. The point is that the number exists at all:
 * nothing in the repo measured it, so the app crossed this line in v0.13.4
 * and nobody could see it happen until a 1-star review four months later.
 */
export const COMFORTABLE_FREE_BYTES = 4 * 1024;

/** Long enough for a cold simulator to load an app and print two lines. */
const LAUNCH_TIMEOUT_MS = 45_000;

/**
 * The tier worth checking on every pull request.
 *
 * Headroom is a property of the device's own limit, and the manifest splits
 * sharply: the five 96KB watches have 7-8KB left once the first screen
 * exists, the 128KB tier has 27-53KB, and everything from 512KB up has about
 * 693KB. A fenix cannot plausibly fail this check, so checking one per pull
 * request buys nothing and costs the minutes that make people skip it.
 *
 * The nightly run covers all 120 - that is what catches this assumption
 * being wrong.
 */
export const AT_RISK_LIMIT_BYTES = 128 * 1024;

/** Where each device's last recorded headroom lives. */
const BASELINE_PATH = join(REPO_ROOT, "tools", "memory-baselines.json");

/**
 * A drop worth saying something about.
 *
 * Not zero. Headroom moves a little with any change and a check that
 * complains about every feature is one people stop reading. This is the size
 * of drop that would have made v0.13.4 visible on the pull request that
 * caused it: the Instinct 2 lost about 2.6KB there and nobody saw it for four
 * months.
 */
export const NOTABLE_DROP_BYTES = 2 * 1024;

/**
 * Below this a difference is not reported at all.
 *
 * Run-to-run noise, measured by running the same build repeatedly - see
 * docs/e2e-testing.md. A threshold under this would report the simulator
 * rather than the change.
 */
export const REPORT_FLOOR_BYTES = 128;

/** A drop worth warning about, as a share of what the device has. */
export const DROP_FRACTION = 0.1;

export interface Reading {
    readonly device: string;
    /** Free bytes once the view and its delegate exist, or null if the app
     * never got that far. */
    readonly freeAtReady: number | null;
    /** Free bytes with the settings menu built on top of that - the most the
     * app is known to hold at once. Null for a build whose probe predates
     * this stage. See headroom(). */
    readonly freeAtPeak: number | null;
    readonly totalMemory: number | null;
    readonly failure: string | null;
}

/** The MEMPROBE line for one stage, as the app prints it. */
export function parseProbe(output: string, stage: string): { total: number; used: number; free: number } | null {
    const pattern = new RegExp(`MEMPROBE ${stage} total=(\\d+) used=(\\d+) free=(\\d+)`);
    const match = pattern.exec(output);
    if (match?.[1] === undefined || match[2] === undefined || match[3] === undefined) {
        return null;
    }
    return { total: Number(match[1]), used: Number(match[2]), free: Number(match[3]) };
}

/**
 * The number that decides whether a watch can run this app.
 *
 * A caveat that belongs next to the number: this measures the *probe* build,
 * which carries the probe. It is not the .prg that ships, so a regression
 * that lands only in code the probe build compiles differently will not
 * show up here - #188's own 208 bytes were exactly that, an empty helper in
 * the shipped build which the probe build never had. What this catches is a
 * change to shared code, which is nearly all of them, and it is why the
 * per-device e2e suite stays the thing that actually opens the menu.
 *
 * The peak where there is one, because the first screen is not where the app
 * runs out. #188's 208-byte regression started fine on descentg1, instinct2
 * and instinct2x and died opening settings; measured on instinct2, the first
 * screen leaves 7,296 bytes and the settings menu leaves 2,016. A check
 * reading only the first screen is reading the wrong number by a factor of
 * three.
 */
export function headroom(reading: Reading): number | null {
    return reading.freeAtPeak ?? reading.freeAtReady;
}

/** What the run said, in the words a reader can act on. */
export function describe(reading: Reading): string {
    const kb = (bytes: number): string => `${String(Math.round(bytes / 1024))}KB`;
    if (reading.failure !== null) {
        return `${reading.device}: ${reading.failure}`;
    }
    if (reading.freeAtReady === null) {
        return `${reading.device}: never reported - the app did not reach its first screen`;
    }
    const total = reading.totalMemory === null ? "" : ` of ${kb(reading.totalMemory)}`;
    const first = `${reading.device}: ${kb(reading.freeAtReady)} free${total} once the first screen exists`;
    if (reading.freeAtPeak === null) {
        return first;
    }
    // Bytes rather than KB for the peak: this is the tight one, and "2KB"
    // hides the difference between 2,016 bytes and 2,800.
    return `${first}, ${String(reading.freeAtPeak)} bytes with the settings menu on top`;
}

/** Failing: crashed, never reported, or down to the last few KB. */
export function isCritical(reading: Reading): boolean {
    const free = headroom(reading);
    return reading.failure !== null || free === null || free < CRITICAL_FREE_BYTES;
}

/** Working, but with less room than anything else on the shelf. */
/** The recorded headroom per device, empty when nothing has been recorded. */
export function loadBaselines(): Map<string, number> {
    if (!existsSync(BASELINE_PATH)) {
        return new Map();
    }
    const parsed: unknown = JSON.parse(readFileSync(BASELINE_PATH, "utf8"));
    const baselines = new Map<string, number>();
    if (typeof parsed !== "object" || parsed === null) {
        return baselines;
    }
    for (const [device, free] of Object.entries(parsed as Record<string, unknown>)) {
        if (typeof free === "number") {
            baselines.set(device, free);
        }
    }
    return baselines;
}

/** How this reading compares with what was recorded, in words. */
export function compareWithBaseline(reading: Reading, baseline: number | undefined): string | null {
    const free = headroom(reading);
    if (baseline === undefined || free === null) {
        return null;
    }
    const delta = free - baseline;
    if (Math.abs(delta) < REPORT_FLOOR_BYTES) {
        return null;
    }
    const size = `${String(Math.abs(delta))} bytes`;
    return delta < 0 ? `${size} less than recorded` : `${size} more than recorded`;
}

/**
 * How big a drop has to be before it is worth a warning, for this baseline.
 *
 * A flat 2KB was calibrated against the first-screen number, where the
 * devices have 7-30KB. Against the peak it is useless: instinct2 peaks at
 * about 2,064 free bytes, so a flat 2KB drop can never fire on the device
 * that most needs it - the app would already be dead. A proportion of what
 * the device actually has is the same question asked at the right scale.
 *
 * The floor is not arbitrary either: the same build measured four times
 * running gave the same number to the byte, so anything above the noise is
 * a real change.
 */
export function notableDropBytes(baseline: number): number {
    return Math.max(REPORT_FLOOR_BYTES, Math.min(NOTABLE_DROP_BYTES, Math.round(baseline * DROP_FRACTION)));
}

export function isNotableDrop(reading: Reading, baseline: number | undefined): boolean {
    const free = headroom(reading);
    if (baseline === undefined || free === null) {
        return false;
    }
    return baseline - free >= notableDropBytes(baseline);
}

export function isTight(reading: Reading): boolean {
    const free = headroom(reading);
    return !isCritical(reading) && free !== null && free < COMFORTABLE_FREE_BYTES;
}

/**
 * A simulator, started if there is not one already.
 *
 * monkeydo does not start one and does not say so clearly when there is
 * none - it prints "Unable to connect to simulator" and exits, which reads
 * like the app failing. Starting it here is what makes this a single command
 * rather than a thing you have to set up first.
 */
function ensureSimulator(): void {
    if (spawnSync("pgrep", ["-f", "ConnectIQ.app/Contents/MacOS/simulator"]).status === 0) {
        return;
    }
    if (spawnSync("pgrep", ["-f", "bin/simulator"]).status === 0) {
        return;
    }
    if (process.platform === "linux") {
        // The CI container has no display, and the simulator will not start
        // without one - the same Xvfb the e2e suite brings up, for the same
        // reason. `simulator` rather than `connectiq` here: the launcher
        // script is macOS-only.
        //
        // Mirrors platform-linux.ts's startSimulator(), because the first
        // version of this did not and reported "the simulator was not
        // reachable" for all twenty devices while looking like a check. Two
        // things it got wrong: `simulator` was spelled as a bare command
        // rather than resolved out of the SDK, and there was no window
        // manager. Keep this in step with that one.
        process.env["DISPLAY"] ??= ":1";
        if (spawnSync("pgrep", ["-f", `Xvfb ${process.env["DISPLAY"]}`]).status !== 0) {
            spawn("Xvfb", [process.env["DISPLAY"], "-screen", "0", "1400x1400x24"], {
                detached: true,
                stdio: "ignore",
            }).unref();
            spawnSync("sleep", ["3"]);
        }
        if (spawnSync("pgrep", ["-f", "openbox"]).status !== 0) {
            spawn("openbox", [], { detached: true, stdio: "ignore", env: process.env }).unref();
        }
        const simulatorBin = resolveTool("simulator", homedir(), process.env["PATH"] ?? "");
        spawn(simulatorBin, [], { detached: true, stdio: "ignore", env: process.env }).unref();
        spawnSync("sleep", ["12"]);
        return;
    }
    const connectiq = resolveTool("connectiq", homedir(), process.env["PATH"] ?? "");
    spawn(connectiq, [], { detached: true, stdio: "ignore" }).unref();
    // The simulator takes a while to be ready for a connection, and monkeydo
    // will not queue one - the same wait tester.sh takes, doubled, because
    // this runs once for a whole batch rather than per device.
    spawnSync("sleep", ["12"]);
}

/**
 * One device: build with the probe in, run it, read what it printed.
 *
 * Stops as soon as the app has said what it came to say. monkeydo stays
 * attached for as long as the app runs, so waiting for it to exit costs a
 * timeout per device - 63 seconds each, or two hours across the manifest,
 * for a number that arrives in the first ten. Killing it at the "ready" line
 * is what makes checking every device we claim to support affordable.
 */
async function measure(
    device: string,
    monkeyc: string,
    monkeydo: string,
    key: string,
    outDir: string,
): Promise<Reading> {
    const prg = join(outDir, `${device}.prg`);
    const build = spawnSync(
        monkeyc,
        ["-f", join(REPO_ROOT, "monkey.probe.jungle"), "-d", device, "-o", prg, "-y", key, "-l", "3"],
        { cwd: REPO_ROOT, encoding: "utf8" },
    );
    if (build.status !== 0) {
        return { device, freeAtReady: null, freeAtPeak: null, totalMemory: null, failure: `did not build\n${build.stderr}` };
    }

    const output = await new Promise<string>((resolve) => {
        // Its own process group: monkeydo is a wrapper script whose real
        // work is a JVM child, and killing only the wrapper leaves that JVM
        // alive holding the pipes - which across 120 devices is 120 orphaned
        // JVMs, and is what kept this process alive for 1h42m after it had
        // already printed its results.
        const child = spawn(monkeydo, [prg, device], { cwd: REPO_ROOT, detached: true });
        let seen = "";
        let done = false;
        const finish = (): void => {
            if (done) {
                return;
            }
            done = true;
            clearTimeout(timer);
            const pid = child.pid;
            if (pid !== undefined) {
                try {
                    process.kill(-pid, "SIGKILL");
                } catch {
                    child.kill("SIGKILL");
                }
            }
            resolve(seen);
        };
        const timer = setTimeout(finish, LAUNCH_TIMEOUT_MS);
        const read = (chunk: Buffer): void => {
            seen += chunk.toString("utf8");
            // Everything worth knowing is decided by one of these three.
            if (/MEMPROBE peak|Out Of Memory|Unable to connect/i.test(seen)) {
                finish();
            }
        };
        child.stdout.on("data", read);
        child.stderr.on("data", read);
        child.on("error", finish);
        child.on("exit", finish);
    });

    if (/Unable to connect/i.test(output)) {
        return { device, freeAtReady: null, freeAtPeak: null, totalMemory: null, failure: "the simulator was not reachable" };
    }
    if (/Out Of Memory/i.test(output)) {
        return { device, freeAtReady: null, freeAtPeak: null, totalMemory: null, failure: "ran out of memory before its first screen" };
    }
    const ready = parseProbe(output, "ready");
    const entry = parseProbe(output, "entry");
    const peak = parseProbe(output, "peak");
    return {
        device,
        freeAtReady: ready?.free ?? null,
        freeAtPeak: peak?.free ?? null,
        totalMemory: ready?.total ?? entry?.total ?? null,
        failure: null,
    };
}

/**
 * Every manifest device at or below `limit`, in manifest order, and how many
 * of them the answer is actually known for.
 *
 * A device with no SDK files here has no readable memory limit, and the
 * filter cannot include it. That is fine in the CI container, which has all
 * 120; it is not fine in silence. Run locally against an SDK with one device
 * installed, the first version of this selected that one device, measured it
 * and printed "every device can hold the app" - a sentence about twenty
 * watches that had looked at one. `checked` is what makes that visible.
 */
export function atRiskSelection(limit: number, devicesDir: string): { devices: string[]; checked: number; total: number } {
    const devices = manifestDevices(readFileSync(join(REPO_ROOT, "manifest.xml"), "utf8"));
    const limits = readMemoryLimits(devicesDir, devices);
    return {
        devices: devices.filter((device) => (limits.get(device) ?? Infinity) <= limit),
        checked: limits.size,
        total: devices.length,
    };
}

/** Every manifest device at or below `limit`, in manifest order. */
export function devicesUpTo(limit: number, devicesDir: string): string[] {
    return atRiskSelection(limit, devicesDir).devices;
}

async function main(): Promise<void> {
    const args = process.argv.slice(2);
    const record = args.includes("--record");
    const devicesDir =
        args.find((arg) => arg.startsWith("--devices-dir="))?.split("=")[1] ??
        join(homedir(), ".Garmin", "ConnectIQ", "Devices");
    const named = args.filter((arg) => !arg.startsWith("--"));
    let devices: string[];
    if (args.includes("--at-risk")) {
        const selection = atRiskSelection(AT_RISK_LIMIT_BYTES, devicesDir);
        devices = selection.devices;
        console.log(
            `${String(selection.devices.length)} device(s) at or below ` +
                `${String(AT_RISK_LIMIT_BYTES / 1024)}KB, from ${String(selection.checked)} of ` +
                `${String(selection.total)} manifest devices with SDK files under ${devicesDir}`,
        );
        if (selection.checked < selection.total) {
            console.warn(
                `::warning::${String(selection.total - selection.checked)} manifest device(s) have no SDK ` +
                    "files here, so their memory limit could not be read and they were not measured. " +
                    "Install them in the SDK manager, or run this where they are present - CI's container has all of them.",
            );
        }
    } else if (args.includes("--all")) {
        devices = manifestDevices(readFileSync(join(REPO_ROOT, "manifest.xml"), "utf8"));
    } else {
        devices = named;
    }
    if (devices.length === 0) {
        console.error("usage: memory-headroom.ts [--at-risk|--all|<device>...] [--record]");
        process.exitCode = 1;
        return;
    }
    const monkeyc = resolveTool("monkeyc", homedir(), process.env["PATH"] ?? "");
    const monkeydo = resolveTool("monkeydo", homedir(), process.env["PATH"] ?? "");
    const key = join(REPO_ROOT, "developer_key.der");
    if (!existsSync(key)) {
        console.error("developer_key.der is missing - run make build once to create it");
        process.exitCode = 1;
        return;
    }
    const outDir = join(REPO_ROOT, "bin", "memory-headroom");
    mkdirSync(outDir, { recursive: true });
    ensureSimulator();

    const readings: Reading[] = [];
    for (const device of devices) {
        readings.push(await measure(device, monkeyc, monkeydo, key, outDir));
    }
    const baselines = loadBaselines();
    for (const reading of readings) {
        const drift = compareWithBaseline(reading, baselines.get(reading.device));
        console.log(drift === null ? describe(reading) : `${describe(reading)} (${drift})`);
    }

    if (record) {
        const updated: Record<string, number> = {};
        for (const [device, free] of [...baselines.entries()].sort(([a], [b]) => a.localeCompare(b))) {
            updated[device] = free;
        }
        for (const reading of readings) {
            const free = headroom(reading);
            if (free !== null) {
                updated[reading.device] = free;
            }
        }
        const sorted: Record<string, number> = {};
        for (const device of Object.keys(updated).sort((a, b) => a.localeCompare(b))) {
            sorted[device] = updated[device] ?? 0;
        }
        writeFileSync(BASELINE_PATH, `${JSON.stringify(sorted, null, 2)}\n`);
        console.log(`\nrecorded ${String(readings.length)} device(s) in tools/memory-baselines.json`);
        return;
    }

    for (const reading of readings) {
        if (isNotableDrop(reading, baselines.get(reading.device))) {
            const lost = (baselines.get(reading.device) ?? 0) - (headroom(reading) ?? 0);
            console.warn(
                `::warning::${reading.device} lost ${String(lost)} bytes of headroom in this change. ` +
                    "That is the size of drop that made the app stop starting on the Instinct 2, and it " +
                    "went unnoticed for four months. Re-record with `make memory-headroom-record` if it is " +
                    "the price of something worth having.",
            );
        }
    }
    for (const reading of readings.filter(isTight)) {
        console.warn(
            `::warning::${reading.device} is down to ${String(Math.round((headroom(reading) ?? 0) / 1024))}KB ` +
                "once its first screen exists. It works, but there is not much room for the next thing added.",
        );
    }
    const failures = readings.filter(isCritical);
    if (failures.length > 0) {
        console.error("");
        for (const reading of failures) {
            console.error(
                `::error::${reading.device} cannot hold the app. This is what shipped on the Instinct 2 for ` +
                    "four months: it compiled, and it could not start. Compile something out for this device " +
                    "in the jungles - see tools/reduced-devices.ts for how the reduced build is chosen.",
            );
        }
        process.exitCode = 1;
        return;
    }
    console.log(`\nall ${String(readings.length)} device(s) measured can hold the app`);
}

if (process.argv[1] !== undefined && import.meta.url.endsWith(process.argv[1].replace(/^.*\//, ""))) {
    await main();
    // Explicitly, rather than by running out of work. Xvfb, the window
    // manager and the simulator are all detached children, and node will sit
    // on those handles indefinitely once main() returns: the first version of
    // this printed every device's result and then hung for 1h42m, holding a
    // pull request open, until the run was cancelled by hand. A check that
    // hangs instead of reporting is worse than no check.
    process.exit(process.exitCode ?? 0);
}
