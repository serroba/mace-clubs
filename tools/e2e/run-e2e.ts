#!/usr/bin/env node
// Runs the e2e suite for one device, one file at a time.
//
// The suite is the shared files in this directory plus one variant
// directory: full/ or reduced/, chosen by MACE_E2E_SUITE. Most screens look
// the same on every watch and live here; the two that do not - the settings
// menu, which loses its history row, and the rest options menu, whose labels
// are shortened - have a file in each variant instead of a conditional in
// one file. A conditional would put the jungle's device list inside an
// assertion, where it would have to stay right in two places at once, and
// the reduced devices are chosen by their memory rather than by name (see
// tools/reduced-devices.ts).
//
// `node --test a.ts b.ts` runs separate test files concurrently by default,
// and --test-concurrency=1 did not reliably serialize them in practice -
// two files' Simulator.launch() calls raced to kill/relaunch the one
// simulator process both need exclusive use of. Spawning each file as its
// own `node --test <file>` invocation and awaiting it before starting the
// next one sidesteps that scheduling entirely, which is worth the small
// extra process-spawn overhead for a suite this size.

import { execFileSync, spawn } from "node:child_process";
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { killSimulatorProcess, simulatorWindowExists } from "./simulator.ts";

const E2E_DIR = fileURLToPath(new URL(".", import.meta.url));

const SUITES = ["full", "reduced"] as const;
type Suite = (typeof SUITES)[number];

/** Which variant directory to run alongside the shared files. Defaults to
 * full: that is what all but five of the 120 devices ship. */
function selectedSuite(): Suite {
    const requested = process.env["MACE_E2E_SUITE"];
    if (requested === undefined || requested.length === 0) {
        return "full";
    }
    if ((SUITES as readonly string[]).includes(requested)) {
        return requested as Suite;
    }
    throw new Error(`MACE_E2E_SUITE must be one of ${SUITES.join(", ")}, not "${requested}"`);
}

// connectiq is launched detached (its own process group) so it survives a
// child test process exiting between presses - but that also means a
// Ctrl-C here, which only signals this process's own group, would orphan
// it rather than clean it up. Catch that case explicitly instead of
// leaving a JVM process to silently sit on memory until some later run's
// pre-kill notices it.
for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.on(signal, () => {
        killSimulatorProcess();
        process.exit(signal === "SIGINT" ? 130 : 143);
    });
}

async function runFile(fileName: string): Promise<number> {
    return await new Promise((resolve) => {
        const child = spawn(
            process.execPath,
            ["--experimental-strip-types", "--disable-warning=ExperimentalWarning", "--test", fileName],
            { cwd: E2E_DIR, stdio: "inherit" },
        );
        child.on("exit", (code) => {
            resolve(code ?? 1);
        });
    });
}

/**
 * Seconds since the last real keyboard or mouse input. A large value means
 * the display has very likely slept or locked, which is the usual reason the
 * simulator never paints a window - see docs/e2e-testing.md.
 */
function displayIdleSeconds(): number | null {
    if (process.platform !== "darwin") {
        return null;
    }
    try {
        const out = execFileSync("ioreg", ["-c", "IOHIDSystem"], { encoding: "utf8" });
        const match = /"HIDIdleTime"\s*=\s*(\d+)/.exec(out);
        return match?.[1] === undefined ? null : Math.round(Number(match[1]) / 1e9);
    } catch {
        return null;
    }
}

/**
 * Explains a failure that is about this machine rather than about the app,
 * and returns true if the run should stop.
 *
 * Without this the suite ploughs on: a locked screen fails every file
 * identically at the 30s launch timeout, so `make release-*` and the release
 * tag hook spend five minutes to tell you something the first failure already
 * knew. Checked only after a real failure, so it cannot misfire on a healthy
 * run that simply has an idle display.
 */
/**
 * Did this file fail because the simulator is not there, rather than because
 * the app is wrong?
 *
 * The simulator is not a reliable process. Across one day of adding devices
 * it failed three different ways - "monkeydo could not reach the simulator
 * after 8 attempts", a SIGSEGV that left a 1.8MB core dump beside the
 * driver, and a file whose test outlived its parent because the app never
 * painted. None of them were the app, and every one of them was green on a
 * rerun.
 *
 * That matters more the more devices there are. Twelve jobs across two
 * workflows means a per-job flake rate that is nearly invisible still turns
 * up somewhere on most pull requests, and a suite that is red for reasons
 * nobody believes gets rerun by reflex - which is exactly how a real failure
 * gets waved through.
 */
function abortsForEnvironment(): boolean {
    if (simulatorWindowExists()) {
        return false;
    }
    const idle = displayIdleSeconds();
    console.error("\nThe simulator has no window, so no further test file can pass.");
    if (idle !== null && idle > 300) {
        console.error(
            `The display has been idle for ${String(idle)}s and has very likely slept or locked. ` +
                "caffeinate keeps an awake display awake but cannot unlock one - unlock it and rerun.",
        );
    } else {
        console.error(
            "Check that the simulator can start and that the display is awake and unlocked " +
                "(see docs/e2e-testing.md, \"Known flakiness\").",
        );
    }
    return true;
}

async function testFiles(dir: string, prefix: string): Promise<string[]> {
    const names = await readdir(dir);
    return names
        .filter((name) => name.endsWith(".e2e.test.ts"))
        .sort()
        .map((name) => `${prefix}${name}`);
}

async function main(): Promise<void> {
    const suite = selectedSuite();
    const files = [
        ...(await testFiles(E2E_DIR, "")),
        ...(await testFiles(join(E2E_DIR, suite), `${suite}/`)),
    ];
    if (files.length === 0) {
        console.error("no *.e2e.test.ts files found");
        process.exitCode = 1;
        return;
    }
    console.log(`running the ${suite} suite: ${String(files.length)} file(s)`);

    let failures = 0;
    for (const file of files) {
        console.log(`\n=== ${file} ===`);
        let code = await runFile(file);
        // One retry, and only when the simulator is missing rather than the
        // assertions failing. A file that fails on its own terms fails
        // straight away: retrying those would turn a real regression into an
        // intermittent one, which is worse than the flake this is for.
        if (code !== 0 && !simulatorWindowExists()) {
            console.error(`::warning::the simulator is gone after ${file} - retrying it once`);
            killSimulatorProcess();
            await new Promise((resolve) => setTimeout(resolve, 5000));
            code = await runFile(file);
        }
        if (code !== 0) {
            failures += 1;
            if (abortsForEnvironment()) {
                console.error(`Stopped after ${file}; ${String(files.length - failures)} file(s) not run.`);
                process.exitCode = 1;
                return;
            }
        }
    }

    if (failures > 0) {
        console.error(`\n${String(failures)}/${String(files.length)} e2e test file(s) failed`);
        process.exitCode = 1;
    }
}

await main();
