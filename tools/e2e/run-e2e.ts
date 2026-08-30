#!/usr/bin/env node
// Runs every *.e2e.test.ts file in this directory, one at a time.
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
import { fileURLToPath } from "node:url";

import { killSimulatorProcess, simulatorWindowExists } from "./simulator.ts";

const E2E_DIR = fileURLToPath(new URL(".", import.meta.url));

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

async function main(): Promise<void> {
    const files = (await readdir(E2E_DIR)).filter((name) => name.endsWith(".e2e.test.ts")).sort();
    if (files.length === 0) {
        console.error("no *.e2e.test.ts files found");
        process.exitCode = 1;
        return;
    }

    let failures = 0;
    for (const file of files) {
        console.log(`\n=== ${file} ===`);
        const code = await runFile(file);
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
