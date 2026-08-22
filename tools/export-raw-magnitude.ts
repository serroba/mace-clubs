#!/usr/bin/env node
// Reconstructs the raw ~25Hz accelerometer magnitude stream from a
// calibration recording (needs the swingDebugEnabled/"Swing calibration
// logging" setting on) and writes it as CSV: t,mg - one row per raw sample,
// not one row per second.
//
// Every other tool in this directory (analyze-fit.ts) works from per-second
// aggregates (peak/min/rms), which necessarily throw away the waveform
// shape within each second. This is for feeding the actual waveform into an
// offline peak-detection prototype, e.g.:
//
//     node --experimental-strip-types tools/export-raw-magnitude.ts activity.fit > raw.csv
//     python3 -c "
//     import pandas as pd
//     from scipy.signal import find_peaks
//     df = pd.read_csv('raw.csv')
//     peaks, props = find_peaks(df.mg, height=1800, distance=25, prominence=400)
//     print(len(peaks), 'peaks')
//     "
//
// Everything runs locally; nothing is uploaded anywhere.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { type DecodedFit, dateField, fieldValue, messagesOf, readFit, timestampSeconds } from "./fit-io.ts";

const SAMPLE_RATE_HZ = 25;

// The on-watch writer pads any second with fewer than 25 real samples (the
// first/last partial window of a work phase) with 0 rather than leaving the
// declared array field short. A magnitude of exactly 0 is not physically
// reachable (gravity alone reads ~1000mg), so it is an unambiguous pad
// sentinel here, not real data - and this is exactly where the sample
// actually stops, since the pad always trails whatever real samples came in.
function isPadSentinel(mg: number): boolean {
    return mg === 0;
}

function rawSamplesOf(fit: DecodedFit, record: unknown): number[] {
    const a = fieldValue(fit, record as Parameters<typeof fieldValue>[1], "accel_mag_a");
    const b = fieldValue(fit, record as Parameters<typeof fieldValue>[1], "accel_mag_b");
    const combined: number[] = [];
    for (const part of [a, b]) {
        if (Array.isArray(part)) {
            for (const value of part) {
                if (typeof value === "number") {
                    combined.push(value);
                }
            }
        }
    }
    let last = combined.at(-1);
    while (last !== undefined && isPadSentinel(last)) {
        combined.pop();
        last = combined.at(-1);
    }
    return combined;
}

export function main(argv: readonly string[] = process.argv.slice(2)): number {
    const path = argv[0];
    if (argv.length !== 1 || path === undefined) {
        console.error("usage: export-raw-magnitude.ts activity.fit > raw.csv");
        return 2;
    }
    const fit = readFit(readFileSync(path));
    const records = messagesOf(fit, "recordMesgs");
    let sawAnySamples = false;
    console.log("t,mg");
    for (const record of records) {
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        const samples = rawSamplesOf(fit, record);
        if (at === null || samples.length === 0) {
            continue;
        }
        sawAnySamples = true;
        samples.forEach((mg, i) => {
            const t = at + i / SAMPLE_RATE_HZ;
            console.log(`${t.toFixed(3)},${mg.toString()}`);
        });
    }
    if (!sawAnySamples) {
        console.error(
            "no accel_mag_a/accel_mag_b fields found - record with "
            + "\"Swing calibration logging\" (swingDebugEnabled) turned on",
        );
        return 1;
    }
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
