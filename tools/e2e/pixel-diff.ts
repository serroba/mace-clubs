// Shared "are these two screenshots meaningfully different" check, used by
// both the driver (waiting for a real screen transition) and the visual
// assertion library (comparing against a baseline). Exact byte equality is
// too strict: two captures of the exact same static screen can differ by a
// handful of pixels from screencapture/PNG-encoding jitter alone, which
// would make Simulator.pressUntilChanged() falsely believe a press
// navigated somewhere when it didn't.

import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";

/** Pixels below this are considered capture noise, not a real UI change. */
export const NOISE_TOLERANCE_PIXELS = 6;

export function countDifferingPixels(actualPng: Buffer, otherPng: Buffer): number {
    const a = PNG.sync.read(actualPng);
    const b = PNG.sync.read(otherPng);
    if (a.width !== b.width || a.height !== b.height) {
        return Number.POSITIVE_INFINITY;
    }
    return pixelmatch(a.data, b.data, undefined, a.width, a.height, { threshold: 0.1 });
}

export function screensDiffer(a: Buffer, b: Buffer, tolerance = NOISE_TOLERANCE_PIXELS): boolean {
    return countDifferingPixels(a, b) > tolerance;
}
