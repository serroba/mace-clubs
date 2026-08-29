// Offline gyroscope swing-cycle candidates for labelled calibration FIT files.
//
// This deliberately stays in the local tooling for now. The exported signed
// axes are decimated from 25 Hz to roughly 12.5 Hz, and the detector uses
// future samples plus amplitude-ranked non-maximum suppression. Both are useful
// for establishing whether rotation contains a countable signal, but neither
// should silently become the on-watch production algorithm without a separate
// streaming implementation and validation.

export type GyroSample = readonly [t: number, x: number, y: number, z: number];

export interface GyroPeakOptions {
    readonly smoothingSamples: number;
    readonly thresholdDps: number;
    readonly minGapSeconds: number;
}

export interface GyroPeak {
    readonly t: number;
    readonly rate: number;
}

function smoothedMagnitude(
    samples: readonly GyroSample[],
    smoothingSamples: number,
): GyroPeak[] {
    if (samples.length === 0) {
        return [];
    }
    const width = Math.max(1, Math.trunc(smoothingSamples));
    const left = Math.floor((width - 1) / 2);
    const right = width - left - 1;
    const magnitudes = samples.map(([, x, y, z]) => Math.hypot(x, y, z));
    const prefix = [0];
    for (const value of magnitudes) {
        prefix.push((prefix.at(-1) ?? 0) + value);
    }
    return samples.map(([t], index) => {
        const start = Math.max(0, index - left);
        const end = Math.min(samples.length, index + right + 1);
        const sum = (prefix[end] ?? 0) - (prefix[start] ?? 0);
        return { t, rate: sum / Math.max(1, end - start) };
    });
}

// Find local rotation-rate maxima, then keep the strongest candidate within
// each refractory neighbourhood. Ranking first avoids choosing a small shoulder
// merely because it precedes the main peak of the same physical swing.
export function detectGyroPeaks(
    samples: readonly GyroSample[],
    options: GyroPeakOptions,
): GyroPeak[] {
    const signal = smoothedMagnitude(samples, options.smoothingSamples);
    const candidates: GyroPeak[] = [];
    for (let index = 1; index + 1 < signal.length; index++) {
        const previous = signal[index - 1];
        const current = signal[index];
        const next = signal[index + 1];
        if (previous === undefined || current === undefined || next === undefined) {
            continue;
        }
        if (current.rate >= options.thresholdDps
            && current.rate > previous.rate
            && current.rate >= next.rate) {
            candidates.push(current);
        }
    }
    candidates.sort((a, b) => b.rate - a.rate);
    const selected: GyroPeak[] = [];
    for (const candidate of candidates) {
        if (selected.every((peak) => Math.abs(peak.t - candidate.t) >= options.minGapSeconds)) {
            selected.push(candidate);
        }
    }
    selected.sort((a, b) => a.t - b.t);
    return selected;
}

// Causal counterpart of the offline detector, mirroring the on-watch mace
// counter: trailing average, one-sample-delayed local-maximum confirmation,
// then a refractory interval measured in seconds.
export function detectStreamingGyroPeaks(
    samples: readonly GyroSample[],
    options: GyroPeakOptions,
): GyroPeak[] {
    const signal = smoothedMagnitude(samples, options.smoothingSamples);
    const selected: GyroPeak[] = [];
    let lastPeak = Number.NEGATIVE_INFINITY;
    for (let index = 2; index < signal.length; index++) {
        const previous = signal[index - 2];
        const current = signal[index - 1];
        const next = signal[index];
        if (previous === undefined || current === undefined || next === undefined) {
            continue;
        }
        if (current.rate >= options.thresholdDps
            && current.rate > previous.rate
            && current.rate >= next.rate
            && current.t - lastPeak >= options.minGapSeconds) {
            selected.push(current);
            lastPeak = current.t;
        }
    }
    return selected;
}
