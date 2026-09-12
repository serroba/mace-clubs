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

/**
 * The line-coverage floor for the whole tooling tree, so a badge can quote it
 * honestly.
 *
 * Anchored on the flag that makes this gate the tree-wide one rather than
 * taking the first `--test-coverage-lines` in the file. ci.yml has three of
 * them - the tree, the FIT core and the synthetic-workout fixture - and
 * whichever happens to come first is not a fact worth building a badge on.
 */
export function coverageFloor(workflow: string): number | null {
    const match = /--test-coverage-exclude='tools\/e2e\/\*\*'[\s\S]*?--test-coverage-lines=(\d+)/.exec(workflow);
    return match?.[1] === undefined ? null : Number(match[1]);
}

/**
 * The floor the FIT report core is held to, which is much higher than the
 * tree's and for a different reason: this is the code that reads and writes
 * what a watch recorded, where being wrong is a wrong number in someone's
 * training log.
 */
export function fitCoverageFloor(workflow: string): number | null {
    const match = /--test-coverage-include='tools\/fit-io\.ts'[\s\S]*?--test-coverage-lines=(\d+)/.exec(workflow);
    return match?.[1] === undefined ? null : Number(match[1]);
}

/**
 * How many shards the build sweep runs in, read out of the workflow.
 *
 * The report said "120 across 8 shards" with the 8 written in, in a file
 * whose whole premise is that nothing is restated. It is one `SHARD_COUNT`
 * away.
 */
export function buildShardCount(workflow: string): number | null {
    const start = workflow.indexOf("build-shards:");
    if (start === -1) {
        return null;
    }
    const match = /SHARD_COUNT:\s*"?(\d+)"?/.exec(workflow.slice(start));
    return match?.[1] === undefined ? null : Number(match[1]);
}

/**
 * Devices whose memory headroom is recorded, from the baselines file.
 *
 * The signal the report was missing. Three pull requests built a headroom
 * check because nothing in the repo measured what the app had left, and the
 * quality table - which exists to carry exactly this kind of number - said
 * nothing about it afterwards.
 */
export function recordedHeadroomDevices(baselinesJson: string): number {
    const parsed: unknown = JSON.parse(baselinesJson);
    if (typeof parsed !== "object" || parsed === null) {
        return 0;
    }
    return Object.values(parsed as Record<string, unknown>).filter((free) => typeof free === "number").length;
}

/**
 * The Monkey C function-coverage floor. rafiki has no --fail-under, so the
 * gate is a step in ci.yml reading this env value - which means the badge has
 * something real to quote.
 */
export function monkeyCFloor(workflow: string): number | null {
    const match = /MONKEY_C_COVERAGE_FLOOR:\s*"?(\d+)"?/.exec(workflow);
    return match?.[1] === undefined ? null : Number(match[1]);
}

export function collectSignals(options: {
    manifest: string;
    ci: string;
    e2e: string;
    e2eReduced: string;
    memoryBaselines: string | null;
    lintRules: number | null;
    monkeyCCoverage: string | null;
    typescriptCoverage: string | null;
}): Signal[] {
    const { manifest, ci, e2e, e2eReduced, memoryBaselines, lintRules, monkeyCCoverage, typescriptCoverage } = options;
    const floor = coverageFloor(ci);
    const shards = buildShardCount(ci);
    const signals: Signal[] = [
        {
            name: "Devices supported",
            value: String(manifestDeviceCount(manifest)),
            source: "manifest.xml",
        },
        {
            name: "Devices built every run",
            value:
                shards === null
                    ? String(manifestDeviceCount(manifest))
                    : `${String(manifestDeviceCount(manifest))} across ${String(shards)} shards`,
            source: "ci.yml build-shards",
        },
        {
            name: "Devices running unit tests",
            value: String(matrixDevices(ci, "name: Unit tests").length),
            source: "ci.yml unit matrix",
        },
        {
            // Both workflows, because the reduced build's watches are driven
            // too - just against their own variant of the two screens that
            // differ. Counting only the full suite would report a smaller
            // number every time a device moved to the reduced build, which
            // is exactly backwards.
            name: "Devices driven through the UI",
            value: String(matrixDevices(e2e, "matrix:").length + matrixDevices(e2eReduced, "matrix:").length),
            source: "e2e-linux.yml + e2e-linux-reduced.yml matrices",
        },
    ];
    if (memoryBaselines !== null) {
        signals.push({
            name: "Devices with recorded memory headroom",
            value: String(recordedHeadroomDevices(memoryBaselines)),
            source: "tools/memory-baselines.json",
        });
    }
    if (typescriptCoverage !== null) {
        signals.push({
            name: "TypeScript line coverage (tooling tree, less the e2e driver)",
            value: floor === null ? typescriptCoverage : `${typescriptCoverage} (floor ${String(floor)}%)`,
            source: "node --experimental-test-coverage",
        });
    }
    const fitFloor = fitCoverageFloor(ci);
    if (fitFloor !== null) {
        signals.push({
            name: "FIT report core line coverage",
            value: `floor ${String(fitFloor)}%`,
            source: "ci.yml fit coverage gate",
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
        e2eReduced: read(".github/workflows/e2e-linux-reduced.yml"),
        memoryBaselines: read("tools/memory-baselines.json"),
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
