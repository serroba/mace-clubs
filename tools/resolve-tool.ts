#!/usr/bin/env node
// Resolve local Connect IQ and Rust tools without depending on shell startup.

import { spawnSync } from "node:child_process";
import { accessSync, constants, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";

const CONNECT_IQ_TOOLS = new Set(["connectiq", "monkeyc", "monkeydo", "monkeygraph"]);
// One binary since bombsimon/monkey-c-rs#8; monkey-c-formatter and
// monkey-c-linter were folded into rafiki and no longer build as binaries.
const RUST_TOOLS = new Set(["rafiki"]);

function isExecutableFile(candidate: string): boolean {
    try {
        if (!statSync(candidate).isFile()) {
            return false;
        }
        accessSync(candidate, constants.X_OK);
        return true;
    } catch {
        return false;
    }
}

function which(tool: string, path: string): string | null {
    for (const entry of path.split(delimiter)) {
        if (entry === "") {
            continue;
        }
        const candidate = join(entry, tool);
        if (isExecutableFile(candidate)) {
            return candidate;
        }
    }
    return null;
}

function workingJava(candidate: string): boolean {
    try {
        const result = spawnSync(candidate, ["-version"], { stdio: "ignore", timeout: 5000 });
        return result.status === 0;
    } catch {
        return false;
    }
}

export function resolve(tool: string, home: string, path: string): string {
    const onPath = which(tool, path);
    if (onPath !== null && (tool !== "java" || workingJava(onPath))) {
        return onPath;
    }

    if (tool === "java") {
        const javaHome = process.env["JAVA_HOME"];
        const candidates = [
            javaHome !== undefined && javaHome !== "" ? join(javaHome, "bin/java") : null,
            "/opt/homebrew/opt/openjdk/bin/java",
            "/usr/local/opt/openjdk/bin/java",
        ];
        for (const candidate of candidates) {
            if (candidate !== null && workingJava(candidate)) {
                return candidate;
            }
        }
    }

    if (CONNECT_IQ_TOOLS.has(tool)) {
        const configs = [
            join(home, "Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"),
            join(home, ".Garmin/ConnectIQ/current-sdk.cfg"),
        ];
        for (const config of configs) {
            let sdk: string;
            try {
                sdk = readFileSync(config, "utf8").trim();
            } catch {
                continue;
            }
            const candidate = join(sdk, "bin", tool);
            if (isExecutableFile(candidate)) {
                return candidate;
            }
        }
    }

    if (RUST_TOOLS.has(tool)) {
        const candidate = join(home, ".cargo/bin", tool);
        if (isExecutableFile(candidate)) {
            return candidate;
        }
    }

    // Preserve the conventional command name so Make's doctor target can
    // report an actionable missing-tool error.
    return tool;
}

export function main(argv: readonly string[] = process.argv.slice(2)): number {
    const tool = argv[0];
    if (argv.length !== 1 || tool === undefined) {
        console.error("usage: resolve-tool.ts TOOL");
        return 2;
    }
    console.log(resolve(tool, homedir(), process.env["PATH"] ?? ""));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
