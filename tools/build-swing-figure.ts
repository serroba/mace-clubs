// Builds the website's swinging figure out of a traced revolution.
//
//   swift video/scripts/trace-pose.swift frames/*.jpg > pose.jsonl
//   swift video/scripts/trace-mace.swift pose.jsonl frames > mace.jsonl
//   node --experimental-strip-types tools/build-swing-figure.ts \
//       pose.jsonl mace.jsonl --from 12 --to 66 --step 2 > figure.svg
//
// --from and --to pick the revolution out of the clip, and want to land on
// the same mace angle at both ends or the loop will jump. --step thins the
// frames: the footage is 30fps and the figure does not need all of it, and
// every frame kept is another figure's worth of markup on the page.
//
// The viewBox is measured rather than chosen. The figure is laid out once to
// find how much room the whole revolution needs - the mace reaches much
// further than the body does, and in a different direction every frame - and
// then laid out again inside it.

import { readFileSync } from "node:fs";

import {
    calibrate,
    renderSwingStrip,
    smoothPoses,
    smoothSeries,
    toFigure,
    traceSwing,
    type Figure,
    type MaceSample,
    type PoseFrame,
} from "./swing-figure.ts";

/** How tall the standing subject is drawn, before the box is fitted round
 * him. Everything else is a fraction of this, so it only sets the units. */
const FIGURE_HEIGHT = 150;

/** Frames of smoothing. Seven at 30fps is under a quarter of a second -
 * enough to settle Vision's jitter, short enough to keep the snap in the
 * swing. The radius is smoothed harder because it is the noisier of the two:
 * the centroid of a blurred head wanders along the shaft. */
const POSE_WINDOW = 7;
const RADIUS_WINDOW = 9;

const PAD = 10;

function parseArgs(argv: readonly string[]): {
    posePath: string;
    macePath: string;
    from: number;
    to: number;
    step: number;
} {
    const positional: string[] = [];
    const flags = new Map<string, string>();
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === undefined) continue;
        if (arg.startsWith("--")) {
            flags.set(arg.slice(2), argv[i + 1] ?? "");
            i++;
        } else {
            positional.push(arg);
        }
    }
    const [posePath, macePath] = positional;
    if (posePath === undefined || macePath === undefined) {
        throw new Error("usage: build-swing-figure.ts <pose.jsonl> <mace.jsonl> [--from n --to n --step n]");
    }
    return {
        posePath,
        macePath,
        from: Number(flags.get("from") ?? "0"),
        to: Number(flags.get("to") ?? "-1"),
        step: Number(flags.get("step") ?? "2"),
    };
}

function readJsonl<T>(path: string): T[] {
    return readFileSync(path, "utf8")
        .split("\n")
        .filter((line) => line.trim() !== "")
        .map((line) => JSON.parse(line) as T);
}

function bounds(figures: readonly Figure[]): { minX: number; minY: number; maxX: number; maxY: number } {
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const figure of figures) {
        const points = [...Object.values(figure.joints), figure.grip, figure.maceHead];
        for (const [x, y] of points) {
            minX = Math.min(minX, x);
            minY = Math.min(minY, y);
            maxX = Math.max(maxX, x);
            maxY = Math.max(maxY, y);
        }
    }
    return { minX, minY, maxX, maxY };
}

function main(): void {
    const { posePath, macePath, from, to, step } = parseArgs(process.argv.slice(2));
    const allPoses = readJsonl<PoseFrame>(posePath);
    const allMace = readJsonl<MaceSample>(macePath);

    // Smooth and fit across the whole clip, then cut the loop out of it: a
    // window taken first would lose the samples just outside it that the
    // smoothing and the curve fit both want.
    const smoothed = smoothPoses(allPoses, POSE_WINDOW);
    const traced = traceSwing(allMace);
    const turn = traced.turn;
    const radii = smoothSeries(traced.radius, RADIUS_WINDOW);

    const last = to < 0 ? smoothed.length - 1 : to;
    const indices: number[] = [];
    for (let i = from; i <= last && i < smoothed.length; i += step) indices.push(i);

    function layOut(footX: number, footY: number): Figure[] {
        const cal = calibrate(smoothed, FIGURE_HEIGHT, footX, footY);
        const out: Figure[] = [];
        for (const i of indices) {
            const pose = smoothed[i];
            if (pose === undefined) continue;
            const figure = toFigure(pose, turn[i] ?? 0, radii[i] ?? 0, cal);
            if (figure !== null) out.push(figure);
        }
        return out;
    }

    // Pass one finds the room the revolution needs; pass two puts it there.
    const probe = layOut(0, 0);
    if (probe.length === 0) throw new Error("no frames in the chosen range");
    const box = bounds(probe);
    const width = Math.ceil(box.maxX - box.minX) + PAD * 2;
    const height = Math.ceil(box.maxY - box.minY) + PAD * 2;
    const figures = layOut(PAD - box.minX, PAD - box.minY);

    const groundY = PAD - box.minY;
    process.stdout.write(
        renderSwingStrip(figures, {
            width,
            height,
            figureHeight: FIGURE_HEIGHT,
            groundY,
            label:
                "A figure swinging a steel mace through one full 360, traced frame by frame from a " +
                "recording of the movement: the mace tips back over the shoulder, comes down behind, " +
                "and rises up the front, while the knees fold to take the weight through the bottom.",
            indent: "        ",
        }) + "\n",
    );
    process.stderr.write(
        `frames ${String(figures.length)}  viewBox ${String(width)}x${String(height)}  ` +
            `turn ${String(Math.round(turn[from] ?? 0))} to ${String(Math.round(turn[last] ?? 0))}\n`,
    );
}

main();
