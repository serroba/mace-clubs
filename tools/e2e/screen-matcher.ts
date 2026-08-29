// Visual-regression assertions for e2e screenshots, in the spirit of
// Playwright's `expect(page).toHaveScreenshot()`: compares a live capture
// against a saved baseline PNG with pixelmatch (the same library Playwright
// uses internally for this), and writes a diff image on mismatch.
//
// First run for a given name writes the baseline instead of comparing -
// review it once (open tools/e2e/baselines/<name>.png), then commit it.
// To intentionally update a baseline after a real UI change, delete the
// file (or set UPDATE_BASELINES=1) and rerun.

import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";

const BASELINE_DIR = fileURLToPath(new URL("baselines", import.meta.url));
const DIFF_DIR = fileURLToPath(new URL(".diffs", import.meta.url));
const DEFAULT_MAX_DIFF_PIXELS = 40; // font hinting / AA noise between runs is normal

export interface ScreenshotMatchOptions {
    maxDiffPixels?: number;
}

export async function expectScreenshotMatches(
    actualPng: Buffer,
    baselineName: string,
    options: ScreenshotMatchOptions = {},
): Promise<void> {
    await mkdir(BASELINE_DIR, { recursive: true });
    const baselinePath = join(BASELINE_DIR, `${baselineName}.png`);

    if (process.env["UPDATE_BASELINES"] === "1" || !existsSync(baselinePath)) {
        await writeFile(baselinePath, actualPng);
        console.log(`[baseline] wrote ${baselinePath} - review it, then commit it`);
        return;
    }

    const actual = PNG.sync.read(actualPng);
    const expected = PNG.sync.read(await readFile(baselinePath));
    if (actual.width !== expected.width || actual.height !== expected.height) {
        throw new Error(
            `screenshot "${baselineName}" is ${String(actual.width)}x${String(actual.height)}, ` +
                `baseline is ${String(expected.width)}x${String(expected.height)}`,
        );
    }

    const diff = new PNG({ width: actual.width, height: actual.height });
    const diffPixels = pixelmatch(actual.data, expected.data, diff.data, actual.width, actual.height, {
        threshold: 0.1,
    });

    const maxDiffPixels = options.maxDiffPixels ?? DEFAULT_MAX_DIFF_PIXELS;
    if (diffPixels > maxDiffPixels) {
        await mkdir(DIFF_DIR, { recursive: true });
        const diffPath = join(DIFF_DIR, `${baselineName}.diff.png`);
        await writeFile(diffPath, PNG.sync.write(diff));
        throw new Error(
            `screenshot "${baselineName}" differs from its baseline by ${String(diffPixels)} pixels ` +
                `(max allowed ${String(maxDiffPixels)}) - see ${diffPath}. ` +
                `If this is an intentional UI change, delete ${baselinePath} and rerun to recapture it.`,
        );
    }
}
