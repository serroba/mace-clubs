import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
    collectSignals,
    coverageFloor,
    manifestDeviceCount,
    matrixDevices,
    renderMarkdown,
} from "./quality-report.ts";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath: string): string =>
    readFileSync(join(REPO_ROOT, relativePath), "utf8");

test("device and matrix counts come out of the real files", () => {
    const manifest = read("manifest.xml");
    const ci = read(".github/workflows/ci.yml");
    const e2e = read(".github/workflows/e2e-linux.yml");

    assert.ok(manifestDeviceCount(manifest) > 100, "the manifest should declare the full fleet");
    // Both matrices are hand-picked representatives, so the useful assertion is
    // that they are found at all - a rename of the job or the key would
    // otherwise silently report zero devices as if that were the truth.
    assert.ok(matrixDevices(ci, "name: Unit tests").length >= 5, "unit matrix should be found");
    assert.ok(matrixDevices(e2e, "matrix:").length >= 3, "e2e matrix should be found");
    assert.equal(coverageFloor(ci), 95);
});

// The badges are the reason this file exists. A README number that no longer
// matches the thing it describes is worse than no badge, because it is read as
// a claim the project stands behind.
test("every badge in the README states something still true", () => {
    const readme = read("README.md");
    const manifest = read("manifest.xml");
    const ci = read(".github/workflows/ci.yml");

    const devices = /badge\/devices-(\d+)-/.exec(readme)?.[1];
    assert.equal(
        Number(devices),
        manifestDeviceCount(manifest),
        "the devices badge disagrees with manifest.xml",
    );

    // "%E2%89%A5" is an encoded >=; the badge promises a floor, so the floor
    // has to be the number CI actually fails below.
    const floor = /TypeScript_line_coverage-%E2%89%A5(\d+)%25/.exec(readme)?.[1];
    assert.equal(
        Number(floor),
        coverageFloor(ci),
        "the coverage badge quotes a floor CI does not enforce",
    );

    const rules = /badge\/lint_rules-(\d+)-/.exec(readme)?.[1];
    assert.ok(rules !== undefined, "the lint-rules badge should be present");
    // The count itself is checked against the linter in CI, where rafiki is
    // installed; here we only guard that it is a plausible number rather than
    // a placeholder someone forgot.
    assert.ok(Number(rules) > 0, "lint-rules badge should not read zero");

    for (const workflow of ["ci.yml", "e2e-linux.yml"]) {
        assert.ok(
            readme.includes(`actions/workflows/${workflow}/badge.svg`),
            `README should badge ${workflow}`,
        );
    }
});

test("the report renders a table and omits signals it was not given", () => {
    const signals = collectSignals({
        manifest: '<iq:product id="a"/><iq:product id="b"/>',
        ci: "name: Unit tests\n      matrix:\n        device:\n          - x\n          - y\n--test-coverage-lines=95",
        e2e: "matrix:\n        device:\n          - p\n",
        lintRules: null,
        monkeyCCoverage: null,
        typescriptCoverage: null,
    });
    const names = signals.map((s) => s.name);
    assert.ok(names.includes("Devices supported"));
    assert.ok(!names.some((n) => n.includes("coverage")), "coverage is omitted when unmeasured");
    assert.ok(!names.includes("Lint rules enforced"), "lint count is omitted when unmeasured");

    const table = renderMarkdown(signals);
    assert.match(table, /^\| Signal \| Value \| Derived from \|/);
    assert.match(table, /Devices supported \| 2 /);
});

test("a renamed job or matrix key reports nothing rather than a wrong number", () => {
    assert.deepEqual(matrixDevices("name: Something else\n  device:\n    - a\n", "name: Unit tests"), []);
    assert.deepEqual(matrixDevices("name: Unit tests\n  steps:\n    - run: x\n", "name: Unit tests"), []);
    assert.equal(coverageFloor("no gate here"), null);
});
