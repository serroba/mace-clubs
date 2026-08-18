#!/usr/bin/env node
// Resolve local Connect IQ and Rust tools without depending on shell startup.

import { spawnSync } from "node:child_process";
import { accessSync, constants, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";

const CONNECT_IQ_TOOLS = new Set(["connectiq", "monkeyc", "monkeydo", "monkeygraph"]);
const RUST_TOOLS = new Set(["monkey-c-formatter", "monkey-c-linter", "rafiki"]);

function isExecutableFile(candidate) {
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

function which(tool, path) {
    for (const entry of path.split(delimiter)) {
        if (!entry) {
            continue;
        }
        const candidate = join(entry, tool);
        if (isExecutableFile(candidate)) {
            return candidate;
        }
    }
    return null;
}

function workingJava(candidate) {
    try {
        const result = spawnSync(candidate, ["-version"], { stdio: "ignore", timeout: 5000 });
        return result.status === 0;
    } catch {
        return false;
    }
}

export function resolve(tool, home, path) {
    const onPath = which(tool, path);
    if (onPath && (tool !== "java" || workingJava(onPath))) {
        return onPath;
    }

    if (tool === "java") {
        const javaHome = process.env.JAVA_HOME;
        const candidates = [
            javaHome ? join(javaHome, "bin/java") : null,
            "/opt/homebrew/opt/openjdk/bin/java",
            "/usr/local/opt/openjdk/bin/java",
        ];
        for (const candidate of candidates) {
            if (candidate && workingJava(candidate)) {
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
            let sdk;
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

export function main(argv = process.argv.slice(2)) {
    if (argv.length !== 1) {
        console.error("usage: resolve-tool.js TOOL");
        return 2;
    }
    console.log(resolve(argv[0], homedir(), process.env.PATH ?? ""));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
