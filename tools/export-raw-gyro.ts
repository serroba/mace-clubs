#!/usr/bin/env node
// Reconstructs the raw per-axis gyroscope stream from a calibration
// recording (needs the swingDebugEnabled/"Swing calibration logging" setting
// on) and writes it as CSV: t,x,y,z (deg/s) - one row per raw sample, not one
// row per second.
//
// The on-watch capture is downsampled to every 2nd sample (~12.5Hz, not the
// accelerometer's full 25Hz): a real 25Hz second split across two array
// fields per axis, the same scheme accel_mag_a/b uses, would need six FIT
// developer fields for x/y/z together, and this device caps developer
// fields at 16 per RECORD message - the existing debug fields already use
// nearly all of it (see FitFields.createSwingDebugFields). One field per
// axis at half rate fits instead.
//
// A raw gyro axis is signed and routinely near zero, unlike accel magnitude
// (never exactly 0), so there is no safe "trailing zero means padding" trick
// here - a short final second of a work phase may include a stray
// zero-padded sample indistinguishable from a genuine near-zero reading.
//
// For plotting any rotation plane (XY/YZ/XZ or otherwise) offline, e.g.:
//
//     node --experimental-strip-types tools/export-raw-gyro.ts activity.fit > raw_gyro.csv
//     python3 -c "
//     import pandas as pd
//     import matplotlib.pyplot as plt
//     df = pd.read_csv('raw_gyro.csv')
//     plt.plot(df.x, df.y)
//     plt.savefig('xy.png')
//     "
//
// Everything runs locally; nothing is uploaded anywhere.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { type DecodedFit, dateField, fieldValue, messagesOf, readFit, timestampSeconds } from "./fit-io.ts";

const SAMPLE_RATE_HZ = 25;
const GYRO_AXIS_STRIDE = 2;

function axisValuesOf(fit: DecodedFit, record: unknown, field: string): number[] {
    const value = fieldValue(fit, record as Parameters<typeof fieldValue>[1], field);
    const values: number[] = [];
    if (Array.isArray(value)) {
        for (const entry of value) {
            if (typeof entry === "number") {
                values.push(entry);
            }
        }
    }
    return values;
}

export function main(argv: readonly string[] = process.argv.slice(2)): number {
    const path = argv[0];
    if (argv.length !== 1 || path === undefined) {
        console.error("usage: export-raw-gyro.ts activity.fit > raw_gyro.csv");
        return 2;
    }
    const fit = readFit(readFileSync(path));
    const records = messagesOf(fit, "recordMesgs");
    let sawAnySamples = false;
    console.log("t,x,y,z");
    for (const record of records) {
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        const x = axisValuesOf(fit, record, "gyro_x");
        const y = axisValuesOf(fit, record, "gyro_y");
        const z = axisValuesOf(fit, record, "gyro_z");
        const n = Math.min(x.length, y.length, z.length);
        if (at === null || n === 0) {
            continue;
        }
        sawAnySamples = true;
        for (let i = 0; i < n; i++) {
            const t = at + (i * GYRO_AXIS_STRIDE) / SAMPLE_RATE_HZ;
            console.log(`${t.toFixed(3)},${(x[i] ?? 0).toString()},${(y[i] ?? 0).toString()},${(z[i] ?? 0).toString()}`);
        }
    }
    if (!sawAnySamples) {
        console.error(
            "no gyro_x/gyro_y/gyro_z fields found - record with "
            + "\"Swing calibration logging\" (swingDebugEnabled) turned on",
        );
        return 1;
    }
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
