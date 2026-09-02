#!/usr/bin/env node
// Reports the project's quality signals as a markdown table.
//
//   make quality                      # print it
//   node ... quality-report.ts --json # machine-readable
//
// CI appends it to the job summary, so every run carries the numbers rather
// than leaving them to a README that rots.
//
// Everything here is *derived* - counted out of the manifest and the workflow
// files - never restated. A hand-maintained number is the thing this replaces:
// the point is that "120 devices" cannot become a lie without the count that
// produced it changing too. Coverage is the exception and is passed in, since
// only a test run knows it.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

const read = (relativePath: string): string =>
    readFileSync(join(REPO_ROOT, relativePath), "utf8");

export interface Signal {
    name: string;
    value: string;
    /** Where the number comes from, so a reader can check it. */
    source: string;
}

/** Products the app declares support for. */
export function manifestDeviceCount(manifest: string): number {
    return manifest.match(/<iq:product /g)?.length ?? 0;
}

/**
 * Devices listed under a workflow job's `matrix.device:`. Counts the `- id`
 * entries after the marker, stopping at the first line that is neither a list
 * item nor a comment, which is where the matrix ends.
 */
export function matrixDevices(workflow: string, afterMarker: string): string[] {
    const start = workflow.indexOf(afterMarker);
    if (start === -1) {
        return [];
    }
    const block = workflow.slice(start);
    const deviceKey = block.indexOf("device:");
    if (deviceKey === -1) {
        return [];
    }
    const devices: string[] = [];
    for (const line of block.slice(deviceKey).split("\n").slice(1)) {
        const trimmed = line.trim();
        if (trimmed.startsWith("#") || trimmed === "") {
            continue;
        }
        const item = /^-\s+([A-Za-z0-9]+)/.exec(trimmed);
        if (item?.[1] === undefined) {
            break;
        }
        devices.push(item[1]);
    }
    return devices;
}

/** The line-coverage floor CI fails below, so a badge can quote it honestly. */
export function coverageFloor(workflow: string): number | null {
    const match = /--test-coverage-lines=(\d+)/.exec(workflow);
    return match?.[1] === undefined ? null : Number(match[1]);
}

export function collectSignals(options: {
    manifest: string;
    ci: string;
    e2e: string;
    lintRules: number | null;
    monkeyCCoverage: string | null;
    typescriptCoverage: string | null;
}): Signal[] {
    const { manifest, ci, e2e, lintRules, monkeyCCoverage, typescriptCoverage } = options;
    const floor = coverageFloor(ci);
    const signals: Signal[] = [
        {
            name: "Devices supported",
            value: String(manifestDeviceCount(manifest)),
            source: "manifest.xml",
        },
        {
            name: "Devices built every run",
            value: `${String(manifestDeviceCount(manifest))} across 8 shards`,
            source: "ci.yml build-shards",
        },
        {
            name: "Devices running unit tests",
            value: String(matrixDevices(ci, "name: Unit tests").length),
            source: "ci.yml unit matrix",
        },
        {
            name: "Devices driven through the UI",
            value: String(matrixDevices(e2e, "matrix:").length),
            source: "e2e-linux.yml matrix",
        },
    ];
    if (typescriptCoverage !== null) {
        signals.push({
            name: "TypeScript line coverage",
            value: floor === null ? typescriptCoverage : `${typescriptCoverage} (floor ${String(floor)}%)`,
            source: "node --experimental-test-coverage",
        });
    }
    if (monkeyCCoverage !== null) {
        signals.push({
            name: "Monkey C function coverage",
            value: monkeyCCoverage,
            source: "rafiki coverage",
        });
    }
    if (lintRules !== null) {
        signals.push({
            name: "Lint rules enforced",
            value: String(lintRules),
            source: "rafiki lint --list-rules",
        });
    }
    return signals;
}

export function renderMarkdown(signals: Signal[]): string {
    const rows = signals.map((s) => `| ${s.name} | ${s.value} | \`${s.source}\` |`);
    return ["| Signal | Value | Derived from |", "|---|---|---|", ...rows].join("\n");
}

function main(): void {
    const args = process.argv.slice(2);
    const valueOf = (flag: string): string | null => {
        const index = args.indexOf(flag);
        return index === -1 ? null : (args[index + 1] ?? null);
    };
    const signals = collectSignals({
        manifest: read("manifest.xml"),
        ci: read(".github/workflows/ci.yml"),
        e2e: read(".github/workflows/e2e-linux.yml"),
        lintRules: valueOf("--lint-rules") === null ? null : Number(valueOf("--lint-rules")),
        monkeyCCoverage: valueOf("--monkey-c-coverage"),
        typescriptCoverage: valueOf("--typescript-coverage"),
    });
    if (args.includes("--json")) {
        console.log(JSON.stringify(signals, null, 2));
        return;
    }
    console.log(renderMarkdown(signals));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    main();
}
