import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { resolve } from "./resolve-tool.ts";

function executable(path: string): string {
    mkdirSync(dirname(path), { recursive: true });
    // A failing script, not an empty file: Linux runs empty executables
    // successfully with exit 0, so an empty file would count as working java.
    writeFileSync(path, "#!/bin/sh\nexit 1\n");
    chmodSync(path, 0o755);
    return path;
}

function workingExecutable(path: string): string {
    executable(path);
    writeFileSync(path, "#!/bin/sh\nexit 0\n");
    return path;
}

function withHome<T>(run: (home: string) => T): T {
    const home = mkdtempSync(join(tmpdir(), "mace-resolve-"));
    try {
        return run(home);
    } finally {
        rmSync(home, { recursive: true, force: true });
    }
}

test("path takes precedence", () => {
    withHome((home) => {
        const expected = executable(join(home, "path-bin", "monkeyc"));
        assert.equal(resolve("monkeyc", home, dirname(expected)), expected);
    });
});

test("macos sdk manager config is used", () => {
    withHome((home) => {
        const sdk = join(home, "Garmin SDK");
        const expected = executable(join(sdk, "bin", "monkeyc"));
        const config = join(home, "Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg");
        mkdirSync(dirname(config), { recursive: true });
        writeFileSync(config, `${sdk}/\n`);
        assert.equal(resolve("monkeyc", home, ""), expected);
    });
});

test("linux sdk manager config is used", () => {
    withHome((home) => {
        const sdk = join(home, "connectiq-sdk");
        const expected = executable(join(sdk, "bin", "monkeydo"));
        const config = join(home, ".Garmin/ConnectIQ/current-sdk.cfg");
        mkdirSync(dirname(config), { recursive: true });
        writeFileSync(config, sdk);
        assert.equal(resolve("monkeydo", home, ""), expected);
    });
});

test("cargo bin is used for rust tools", () => {
    withHome((home) => {
        const expected = executable(join(home, ".cargo/bin/rafiki"));
        assert.equal(resolve("rafiki", home, ""), expected);
    });
});

test("missing tool returns conventional name", () => {
    withHome((home) => {
        assert.equal(resolve("monkeyc", home, ""), "monkeyc");
    });
});

test("working java on path is used", () => {
    withHome((home) => {
        const expected = workingExecutable(join(home, "jdk/bin/java"));
        assert.equal(resolve("java", home, dirname(expected)), expected);
    });
});

test("broken java on path is ignored", () => {
    withHome((home) => {
        const broken = executable(join(home, "broken/bin/java"));
        assert.notEqual(resolve("java", home, dirname(broken)), broken);
    });
});
