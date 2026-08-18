#!/usr/bin/env node
// Build the reviewable FIT and visual fixture for the synthetic workout.

import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { Encoder, Profile } from "@garmin/fitsdk";

import { pythonRound } from "./fit-io.js";

export const BASELINE = fileURLToPath(new URL("baselines/synthetic-workout.svg", import.meta.url));
export const START_MS = 1_700_000_000_000;
const SAMPLE_RATE = 25;

export function samples(style, second) {
    const axes = [[], [], []];
    for (let index = 0; index < SAMPLE_RATE; index++) {
        const angle = (2 * Math.PI * index) / SAMPLE_RATE;
        let values;
        if (style === "still") {
            values = [0, 0, 1000];
        } else if (style === "smooth") {
            const amplitude = 560;
            values = [
                pythonRound(amplitude * Math.sin(angle)),
                pythonRound(amplitude * 0.55 * Math.cos(angle)),
                pythonRound(1000 + amplitude * 0.22 * Math.sin(2 * angle)),
            ];
        } else if (style === "irregular") {
            const amplitude = 430 + ((second * 97 + index * 53) % 360);
            values = [
                pythonRound(amplitude * Math.sin(angle + second * 0.17)),
                pythonRound(amplitude * 0.7 * Math.cos(1.3 * angle)),
                pythonRound(1000 + amplitude * 0.3 * Math.sin(2.4 * angle)),
            ];
        } else if (style === "spike") {
            values = index === 12 ? [4200, -900, 1600] : [
                pythonRound(650 * Math.sin(angle)),
                pythonRound(300 * Math.cos(angle)),
                pythonRound(1000 + 160 * Math.sin(2 * angle)),
            ];
        } else {
            throw new Error(`unknown motion style: ${style}`);
        }
        for (const [axis, value] of axes.map((entries, position) => [entries, values[position]])) {
            axis.push(value);
        }
    }
    return axes;
}

function features(x, y, z) {
    const magnitudes = x.map((value, index) =>
        Math.sqrt(value * value + y[index] * y[index] + z[index] * z[index]));
    const mean = magnitudes.reduce((total, value) => total + value, 0) / magnitudes.length;
    const means = [x, y, z].map((axis) => axis.reduce((total, value) => total + value, 0) / axis.length);
    let crossings = 0;
    let previous = 0;
    for (const magnitude of magnitudes) {
        const sign = magnitude > mean ? 1 : magnitude < mean ? -1 : 0;
        if (sign && previous && sign !== previous) {
            crossings += 1;
        }
        if (sign) {
            previous = sign;
        }
    }
    const dynamic = x.map((value, index) =>
        Math.sqrt((value - means[0]) ** 2 + (y[index] - means[1]) ** 2 + (z[index] - means[2]) ** 2));
    const rootMeanSquare = (values) =>
        Math.trunc(Math.sqrt(values.reduce((total, value) => total + value * value, 0) / values.length));
    return [
        rootMeanSquare(magnitudes),
        Math.trunc(Math.max(...magnitudes)),
        crossings,
        rootMeanSquare(dynamic),
        Math.trunc(Math.max(...dynamic)),
    ];
}

export function workout() {
    const timeline = [];
    for (let second = 0; second < 50; second++) {
        let phase;
        let style;
        if (second < 5 || (second >= 25 && second < 30)) {
            [phase, style] = ["rest", "still"];
        } else if (second < 25) {
            [phase, style] = ["work", "smooth"];
        } else {
            [phase, style] = ["work", second === 42 ? "spike" : "irregular"];
        }
        const [x, y, z] = samples(style, second);
        const [rms, peak, crossings, dynamicRms, dynamicPeak] = features(x, y, z);
        timeline.push({
            second, phase, style, x, y, z,
            rms, peak, crossings,
            dynamic_rms: dynamicRms, dynamic_peak: dynamicPeak,
        });
    }
    return timeline;
}

// FIT wire values for fit_base_type_id (profile type fitBaseType); the SDK's
// Utils.FitBaseType indexes are NOT valid field_description content.
const BASE_TYPE = { uint8: 2, string: 7, sint16: 131, uint16: 132, uint32: 134, float32: 136 };

const FIELD_TYPES = [
    [0, "total_sets", "sets", BASE_TYPE.uint16],
    [1, "battery_used", "%", BASE_TYPE.float32],
    [2, "accel_rms", "mg", BASE_TYPE.uint16],
    [3, "accel_peak", "mg", BASE_TYPE.uint16],
    [4, "accel_zc", "crossings", BASE_TYPE.uint8],
    [6, "implement_count", "implements", BASE_TYPE.uint8],
    [7, "implement_weight", "g", BASE_TYPE.uint16],
    [8, "set_number", "set", BASE_TYPE.uint16],
    [10, "phase", "0=rest 1=work", BASE_TYPE.uint8],
    [11, "phase_duration", "s", BASE_TYPE.uint16],
    [14, "set_smoothness", "score", BASE_TYPE.sint16],
    [17, "total_swings", "swings", BASE_TYPE.uint16],
    [18, "swing_count", "swings", BASE_TYPE.uint16],
    [19, "motion_exposure", "mg-s", BASE_TYPE.uint32],
    [20, "motion_peak", "mg", BASE_TYPE.uint16],
    [21, "active_seconds", "s", BASE_TYPE.uint16],
    [22, "weight_volume", "kg-swings", BASE_TYPE.uint32],
    [15, "movement_type", "movement", BASE_TYPE.uint8],
    [16, "working_side", "side", BASE_TYPE.uint8],
    [23, "work_time", "s", BASE_TYPE.uint32],
    [24, "rest_time", "s", BASE_TYPE.uint32],
    [26, "implement_name", "", BASE_TYPE.string],
    [27, "swing_total", "swings", BASE_TYPE.uint16],
    [28, "swing_event", "swings", BASE_TYPE.uint8],
    [29, "swing_cadence", "spm", BASE_TYPE.uint8],
    [30, "smoothness_score", "score", BASE_TYPE.uint8],
];

const DEVELOPER_DATA_ID_MESG = {
    mesgNum: Profile.MesgNum.DEVELOPER_DATA_ID,
    applicationId: Array.from(Buffer.from("6f0f19e1a0e14842a7b70ac011223344", "hex")),
    applicationVersion: 999,
    developerDataIndex: 0,
};

const FIELD_DESCRIPTION_MESGS = FIELD_TYPES.map(([fieldId, name, units, baseType]) => ({
    mesgNum: Profile.MesgNum.FIELD_DESCRIPTION,
    developerDataIndex: 0,
    fieldDefinitionNumber: fieldId,
    fitBaseTypeId: baseType,
    fieldName: name,
    units,
}));

const FIELD_DESCRIPTIONS = Object.fromEntries(FIELD_DESCRIPTION_MESGS.map((mesg) => [
    mesg.fieldName,
    { developerDataIdMesg: DEVELOPER_DATA_ID_MESG, fieldDescriptionMesg: mesg },
]));

export function buildFit(windows, destination) {
    const encoder = new Encoder({ fieldDescriptions: FIELD_DESCRIPTIONS });
    encoder.writeMesg({
        mesgNum: Profile.MesgNum.FILE_ID,
        type: "activity",
        manufacturer: "development",
        product: 1,
        serialNumber: 424242,
        timeCreated: new Date(START_MS),
    });
    encoder.writeMesg(DEVELOPER_DATA_ID_MESG);
    for (const mesg of FIELD_DESCRIPTION_MESGS) {
        encoder.writeMesg(mesg);
    }

    let swingTotal = 0;
    let recentEvents = [];
    let smoothReference = null;
    let smoothTotal = 0;
    let smoothWindows = 0;
    let validWindows = 0;
    for (const window of windows) {
        // The committed fixture mirrors the production record contract. Its
        // deterministic event shape is presentation data; Monkey C tests own
        // the detector and production-pipeline assertions.
        const event = window.phase === "work" && window.second % 2 === 0 ? 1 : 0;
        swingTotal += event;
        recentEvents.push(event);
        recentEvents = recentEvents.slice(-10);
        const cadence = pythonRound(
            (recentEvents.reduce((total, value) => total + value, 0) * 60) / recentEvents.length);
        if (window.phase === "work" && window.dynamic_rms >= 40) {
            if (smoothReference === null) {
                smoothReference = [window.dynamic_rms, window.dynamic_peak, window.crossings];
            } else {
                if (validWindows >= 4) {
                    const differences = [
                        Math.abs(window.dynamic_rms - smoothReference[0]) / Math.max(Math.abs(smoothReference[0]), 40),
                        Math.abs(window.dynamic_peak - smoothReference[1]) / Math.max(Math.abs(smoothReference[1]), 80),
                        Math.abs(window.crossings - smoothReference[2]) / Math.max(Math.abs(smoothReference[2]), 2),
                    ];
                    smoothTotal += Math.max(0, Math.min(100, Math.trunc(
                        100 - 100 * (0.45 * differences[0] + 0.35 * differences[1] + 0.20 * differences[2]))));
                    smoothWindows += 1;
                }
                smoothReference = smoothReference.map((old, index) =>
                    0.8 * old + 0.2 * [window.dynamic_rms, window.dynamic_peak, window.crossings][index]);
            }
            validWindows += 1;
        }
        const smoothScore = smoothWindows ? pythonRound(smoothTotal / smoothWindows) : 0;
        encoder.writeMesg({
            mesgNum: Profile.MesgNum.RECORD,
            timestamp: new Date(START_MS + window.second * 1000),
            heartRate: 68 + pythonRound(window.second * 0.65) + (window.phase === "work" ? 7 : 0),
            developerFields: {
                accel_rms: window.rms,
                accel_peak: window.peak,
                accel_zc: window.crossings,
                swing_total: swingTotal,
                swing_event: event,
                swing_cadence: cadence,
                smoothness_score: smoothScore,
            },
        });
    }

    const laps = [
        [0, 5, 0, 0, -1, 0],
        [5, 20, 1, 1, 88, 20],
        [25, 5, 0, 0, -1, 0],
        [30, 20, 1, 2, 61, 17],
    ];
    laps.forEach(([start, duration, phase, setNumber, smoothness, swings], index) => {
        const segment = windows.slice(start, start + duration);
        encoder.writeMesg({
            mesgNum: Profile.MesgNum.LAP,
            messageIndex: index,
            startTime: new Date(START_MS + start * 1000),
            timestamp: new Date(START_MS + (start + duration) * 1000),
            totalElapsedTime: duration,
            totalTimerTime: duration,
            developerFields: {
                set_number: setNumber,
                phase,
                phase_duration: duration,
                set_smoothness: smoothness,
                movement_type: 4,
                working_side: 3,
                swing_count: swings,
                motion_exposure: segment.reduce((total, item) => total + item.dynamic_rms, 0),
                motion_peak: Math.max(...segment.map((item) => item.dynamic_peak)),
                active_seconds: phase ? duration : 0,
                weight_volume: phase ? 8 * swings : 0,
            },
        });
    });

    encoder.writeMesg({
        mesgNum: Profile.MesgNum.SESSION,
        startTime: new Date(START_MS),
        timestamp: new Date(START_MS + 50_000),
        totalElapsedTime: 50,
        totalTimerTime: 50,
        avgHeartRate: 91,
        maxHeartRate: 107,
        numLaps: laps.length,
        developerFields: {
            total_sets: 2,
            battery_used: 1.5,
            implement_count: 2,
            implement_weight: 4000,
            total_swings: 37,
            work_time: 40,
            rest_time: 10,
            implement_name: "Clubs: 2 x 4 kg",
        },
    });
    encoder.writeMesg({
        mesgNum: Profile.MesgNum.ACTIVITY,
        timestamp: new Date(START_MS + 50_000),
        totalTimerTime: 50,
        numSessions: 1,
    });

    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, encoder.close());
}

const fixed1 = (value) => value.toFixed(1);

export function renderSvg(windows) {
    const [width, height] = [960, 580];
    const [left, right, top, chartBottom] = [72, 28, 92, 400];
    const chartWidth = width - left - right;
    const maximum = Math.max(...windows.map((item) => item.peak));
    const x = (second) => left + (chartWidth * second) / (windows.length - 1);
    const y = (value) => chartBottom - ((chartBottom - top) * value) / maximum;
    const points = (key) => windows.map((item) => `${fixed1(x(item.second))},${fixed1(y(item[key]))}`).join(" ");
    const backgrounds = [];
    for (const [start, duration, phase] of [[0, 5, "Rest"], [5, 20, "Smooth"], [25, 5, "Rest"], [30, 20, "Irregular"]]) {
        const color = phase === "Rest" ? "#e9f0f7" : "#fff0e9";
        backgrounds.push(
            `<rect x="${fixed1(x(start))}" y="${top}" width="${fixed1((chartWidth * duration) / 50)}" `
            + `height="${chartBottom - top}" fill="${color}"/><text x="${fixed1(x(start) + 8)}" y="${top + 20}" `
            + `font-size="13" fill="#6f6961">${phase}</text>`,
        );
    }
    const bars = [];
    for (const [setNumber, score] of [[1, 88], [2, 61]]) {
        const barX = 220 + (setNumber - 1) * 260;
        const barHeight = score * 0.65;
        bars.push(
            `<rect x="${barX}" y="${fixed1(565 - barHeight)}" width="110" height="${fixed1(barHeight)}" `
            + `rx="3" fill="#397a68"/><text x="${barX + 55}" y="${fixed1(553 - barHeight)}" `
            + `text-anchor="middle" font-size="16" fill="#24211d">${score}</text><text x="${barX + 55}" `
            + `y="578" text-anchor="middle" font-size="13" fill="#6f6961">Set ${setNumber}</text>`,
        );
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
<rect width="100%" height="100%" fill="#f7f5f1"/><text x="${left}" y="38" font-family="system-ui,sans-serif" font-size="25" font-weight="600" fill="#24211d">Synthetic motion confidence check</text>
<text x="${left}" y="64" font-family="system-ui,sans-serif" font-size="14" fill="#6f6961">Stillness → smooth periodic swings → rest → irregular swings with one deliberate spike</text>
<g font-family="system-ui,sans-serif">${backgrounds.join("")}
<line x1="${left}" y1="${chartBottom}" x2="${width - right}" y2="${chartBottom}" stroke="#bdb7af"/>
<polyline points="${points("rms")}" fill="none" stroke="#bd3e14" stroke-width="3"/>
<polyline points="${points("peak")}" fill="none" stroke="#e4a02b" stroke-width="2"/>
<text x="${left}" y="425" font-size="13" fill="#bd3e14">Acceleration RMS</text><text x="220" y="425" font-size="13" fill="#b37813">Peak acceleration</text>
<text x="${left}" y="466" font-size="18" font-weight="600" fill="#24211d">Expected smoothness contrast</text>${bars.join("")}</g></svg>`;
}

export function generatedOutputs(directory) {
    const windows = workout();
    const fitDestination = join(directory, "synthetic-workout.fit");
    buildFit(windows, fitDestination);
    return new Map([
        [fitDestination, readFileSync(fitDestination)],
        [join(directory, "synthetic-workout.svg"), renderSvg(windows)],
    ]);
}

function parseArgs(argv) {
    const args = { outputDir: join("build", "synthetic-workout"), check: false };
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === "--output-dir") {
            args.outputDir = argv[++index];
        } else if (argument === "--check") {
            args.check = true;
        } else {
            throw new Error(`unexpected argument: ${argument}`);
        }
    }
    return args;
}

export function main(argv = process.argv.slice(2), baseline = BASELINE) {
    const args = parseArgs(argv);
    const temporary = mkdtempSync(join(tmpdir(), "mace-synthetic-"));
    try {
        const outputs = generatedOutputs(temporary);
        const svg = [...outputs.entries()].find(([path]) => path.endsWith(".svg"))[1];
        if (args.check && (!existsSync(baseline) || readFileSync(baseline, "utf8") !== svg)) {
            throw new Error(`visual baseline differs: regenerate ${baseline}`);
        }
        mkdirSync(args.outputDir, { recursive: true });
        for (const [source, content] of outputs) {
            writeFileSync(join(args.outputDir, source.split("/").pop()), content);
        }
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
    console.log(args.outputDir);
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    try {
        process.exitCode = main();
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
