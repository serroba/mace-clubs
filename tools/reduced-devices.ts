#!/usr/bin/env node
// Which manifest devices are too small to hold the whole app, and whether
// the jungles know it.
//
// The Instinct 2 family is not special. It is simply where the crash was
// reported: a watch-app gets 96KB there against 128KB or more everywhere
// else, and the app grew past that in v0.13.4 (see #172). Five devices in
// the manifest share that ceiling, and the first fix listed three of them by
// hand - so descentg1 and instinctcrossover stayed in the store failing with
// an Out Of Memory Error inside getInitialView(), before drawing a frame,
// for as long as it took someone to ask whether the Instinct 2 was really
// the only one.
//
// So the list is derived rather than maintained. Each device's own
// compiler.json states its watchApp memory limit; this reads them and
// insists that every device at or below the threshold carries the reduced
// build's exclusions. Adding a low-memory device to the manifest without
// wiring it up now fails the build sweep instead of the store.

import { readFileSync } from "node:fs";
import { join } from "node:path";

/** Devices at or below this get the reduced build. 96KB is where the app
 * does not fit; the next tier up is 128KB, where instinct3solar45mm runs
 * with 60KB to spare, so the boundary is not a close call. */
export const SMALL_MEMORY_BYTES = 96 * 1024;

/** The annotations a reduced build compiles out. Order is not significant;
 * the check compares them as a set. */
export const REDUCED_EXCLUSIONS = [
    "swingDebug",
    "history",
    "customWorkout",
    "motionExport",
    "menuLabelPrefix",
] as const;

/** Product ids in the order the manifest lists them. */
export function manifestDevices(manifestXml: string): string[] {
    return [...manifestXml.matchAll(/<iq:product\s+id="([^"]+)"/g)].map((match) => match[1] ?? "");
}

/** A device's watch-app memory limit, or null if its compiler.json does not
 * state one (which is not a failure - it means the SDK files are not here). */
export function watchAppMemoryLimit(compilerJson: string): number | null {
    const parsed: unknown = JSON.parse(compilerJson);
    if (typeof parsed !== "object" || parsed === null || !("appTypes" in parsed)) {
        return null;
    }
    const appTypes = (parsed as { appTypes?: unknown }).appTypes;
    if (!Array.isArray(appTypes)) {
        return null;
    }
    for (const entry of appTypes as { type?: unknown; memoryLimit?: unknown }[]) {
        if (entry.type === "watchApp" && typeof entry.memoryLimit === "number") {
            return entry.memoryLimit;
        }
    }
    return null;
}

/** The devices a jungle gives reduced exclusions to, mapped to the set of
 * annotations each one excludes on top of BASE_EXCLUDES. */
export function jungleReducedDevices(jungle: string): Map<string, Set<string>> {
    const found = new Map<string, Set<string>>();
    for (const line of jungle.split("\n")) {
        const match = /^([A-Za-z0-9_]+)\.excludeAnnotations\s*=\s*\$\(BASE_EXCLUDES\);(.+)$/.exec(line.trim());
        if (match?.[1] === undefined || match[2] === undefined) {
            continue;
        }
        found.set(
            match[1],
            new Set(
                match[2]
                    .split(";")
                    .map((part) => part.trim())
                    .filter((part) => part.length > 0),
            ),
        );
    }
    return found;
}

export interface Problem {
    readonly device: string;
    readonly detail: string;
}

/**
 * Every disagreement between the devices' own memory limits and the jungle.
 *
 * `memoryLimits` holds only the devices whose SDK files were readable, so a
 * partial install reports on what it can rather than failing wholesale - the
 * check is worth running locally, where the SDK usually has a handful of
 * devices, as well as in CI, where it has all of them.
 */
export function reducedBuildProblems(
    devices: string[],
    memoryLimits: Map<string, number>,
    jungle: Map<string, Set<string>>,
): Problem[] {
    const expected = new Set(REDUCED_EXCLUSIONS);
    const problems: Problem[] = [];
    for (const device of devices) {
        const limit = memoryLimits.get(device);
        if (limit === undefined) {
            continue;
        }
        const wired = jungle.get(device);
        if (limit <= SMALL_MEMORY_BYTES) {
            if (wired === undefined) {
                problems.push({
                    device,
                    detail:
                        `has ${String(Math.round(limit / 1024))}KB for a watch-app and no reduced build. ` +
                        `The app does not fit: it will fail with an Out Of Memory Error before it draws a frame. ` +
                        `Add "${device}.excludeAnnotations = $(BASE_EXCLUDES);${REDUCED_EXCLUSIONS.join(";")}" to every jungle.`,
                });
            } else {
                const missing = [...expected].filter((annotation) => !wired.has(annotation));
                if (missing.length > 0) {
                    problems.push({ device, detail: `is a reduced-build device but does not exclude ${missing.join(", ")}` });
                }
            }
        } else if (wired !== undefined && [...expected].some((annotation) => wired.has(annotation))) {
            problems.push({
                device,
                detail:
                    `has ${String(Math.round(limit / 1024))}KB for a watch-app, which is enough for the whole app, ` +
                    `but is on the reduced build. Its owners are losing features for no reason.`,
            });
        }
    }
    return problems;
}

/** Reads each device's compiler.json out of an SDK device directory. */
export function readMemoryLimits(devicesDir: string, devices: string[]): Map<string, number> {
    const limits = new Map<string, number>();
    for (const device of devices) {
        try {
            const limit = watchAppMemoryLimit(readFileSync(join(devicesDir, device, "compiler.json"), "utf8"));
            if (limit !== null) {
                limits.set(device, limit);
            }
        } catch {
            // No SDK files for this device here; nothing to check against.
        }
    }
    return limits;
}

function main(): void {
    const devicesDir = process.argv[2] ?? join(process.env["HOME"] ?? "", ".Garmin", "ConnectIQ", "Devices");
    const devices = manifestDevices(readFileSync("manifest.xml", "utf8"));
    const limits = readMemoryLimits(devicesDir, devices);
    if (limits.size === 0) {
        console.error(`no device files under ${devicesDir} - nothing to check`);
        process.exitCode = 1;
        return;
    }
    const problems = reducedBuildProblems(devices, limits, jungleReducedDevices(readFileSync("monkey.jungle", "utf8")));
    const small = devices.filter((d) => (limits.get(d) ?? Infinity) <= SMALL_MEMORY_BYTES);
    console.log(`checked ${String(limits.size)} of ${String(devices.length)} manifest devices against ${devicesDir}`);
    console.log(`${String(small.length)} at or below ${String(SMALL_MEMORY_BYTES / 1024)}KB: ${small.join(", ")}`);
    if (problems.length > 0) {
        for (const problem of problems) {
            console.error(`::error::${problem.device} ${problem.detail}`);
        }
        process.exitCode = 1;
        return;
    }
    console.log("every low-memory device is on the reduced build");
}

if (process.argv[1] !== undefined && import.meta.url.endsWith(process.argv[1].replace(/^.*\//, ""))) {
    main();
}
