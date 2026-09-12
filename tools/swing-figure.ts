// Turns a traced swing into the figure on the website.
//
// The input is what video/scripts/trace-pose.swift and trace-mace.swift read
// out of one revolution of real footage: a body pose per frame, and the mace
// head per frame where the brass was bright enough to find. The output is an
// SVG filmstrip - every frame drawn side by side in one wide group, with a
// one-frame window over it - so the whole animation is a single stepped
// translate rather than one animation per frame. That is the same mechanism
// the watch screens' digit strips use.
//
// Two things need care, and both are handled here rather than in the tracers:
//
// - The mace is missing from about a third of the frames, always the same
//   third: through the fast part of the revolution the head smears and loses
//   the saturation it is found by. The angle is recovered instead, by
//   unwrapping what was measured into one continuous turn and fitting a
//   monotone curve through it. A rigid body swinging under gravity cannot do
//   anything surprising in the third of a second between two measured angles.
//
// - Vision jitters a few pixels per joint per frame, which on a figure this
//   size is a visible shiver. Joints are smoothed over a short window before
//   anything is drawn.
//
// What is deliberately NOT normalised away is the vertical compression: the
// subject is a head shorter at the bottom of the swing than at the top,
// because he is loading his knees into it. Scale is taken from his standing
// height once, not per frame, so that stays in.

export type Sample = readonly [number, number, number];
export type Joints = Record<string, Sample>;

export interface PoseFrame {
    readonly file: string;
    readonly found: boolean;
    readonly joints?: Joints;
}

export interface MaceSample {
    readonly file: string;
    readonly found: boolean;
    /** Degrees clockwise from straight up, as the tracer reports it. */
    readonly angle?: number;
    readonly radius?: number;
    /** Which brass threshold found it; the tightest one is the one to trust. */
    readonly floor?: number;
}

/** The tightest brass threshold - the set with no false positives in it. */
const TRUSTED_FLOOR = 85;

/** Beyond this many degrees between neighbouring frames, a sample is not the
 * mace: it is the rug, or the lamp, or a stripe of lit skin. */
const MAX_TURN_PER_FRAME = 26;

function numberAt(values: readonly number[], index: number): number {
    const value = values[index];
    if (value === undefined) throw new RangeError(`index ${String(index)} is out of range`);
    return value;
}

export interface Traced {
    /** One continuous turn, in degrees, for every frame. */
    readonly turn: number[];
    /** How far the head sat from the grip, for every frame. Not constant and
     * not noise: the shaft foreshortens as it tilts out of the camera's
     * plane, which is most of what makes the drawn swing read as depth. */
    readonly radius: number[];
}

/**
 * One continuous turn, per frame, in degrees, from samples that are missing
 * in the middle and occasionally wrong.
 *
 * The revolution only ever goes one way, which is what makes this tractable:
 * unwrap each reading onto whichever multiple of 360 sits nearest its
 * predecessor, drop anything that would need an impossible rate to reach, and
 * fit a monotone curve through what is left.
 */
export function traceSwing(samples: readonly MaceSample[]): Traced {
    const indices: number[] = [];
    const angles: number[] = [];
    let previous: number | null = null;
    let previousIndex = -1;

    for (let i = 0; i < samples.length; i++) {
        const sample = samples[i];
        if (sample === undefined) continue;
        const { angle } = sample;
        if (!sample.found || angle === undefined) continue;
        if ((sample.floor ?? TRUSTED_FLOOR + 1) > TRUSTED_FLOOR) continue;

        if (previous === null) {
            indices.push(i);
            angles.push(angle);
            previous = angle;
            previousIndex = i;
            continue;
        }
        // The representative congruent to this reading that sits closest to
        // where the last one left off.
        const turns = Math.round((previous - angle) / 360);
        const candidate = angle + turns * 360;
        if (Math.abs(candidate - previous) / (i - previousIndex) > MAX_TURN_PER_FRAME) continue;
        indices.push(i);
        angles.push(candidate);
        previous = candidate;
        previousIndex = i;
    }

    if (indices.length < 2) {
        return { turn: new Array<number>(samples.length).fill(0), radius: new Array<number>(samples.length).fill(0) };
    }
    // Radius comes off the same accepted frames, and only those. Averaging
    // over every frame instead lets a rejected reading - or the zero standing
    // in for a frame where nothing was found at all - drag the shaft in, and
    // a mace that shortens through the fast part of the swing looks like it
    // is being swallowed.
    const radii = indices.map((i) => samples[i]?.radius ?? 0);
    return {
        turn: monotoneFit(indices, angles, samples.length),
        radius: interpolate(indices, radii, samples.length),
    };
}

/** Piecewise-linear through the given points, held flat outside them. */
export function interpolate(xs: readonly number[], ys: readonly number[], count: number): number[] {
    const out: number[] = [];
    for (let x = 0; x < count; x++) {
        if (x <= numberAt(xs, 0)) {
            out.push(numberAt(ys, 0));
            continue;
        }
        if (x >= numberAt(xs, xs.length - 1)) {
            out.push(numberAt(ys, ys.length - 1));
            continue;
        }
        let k = 0;
        while (k < xs.length - 2 && numberAt(xs, k + 1) <= x) k++;
        const t = (x - numberAt(xs, k)) / (numberAt(xs, k + 1) - numberAt(xs, k));
        out.push(numberAt(ys, k) * (1 - t) + numberAt(ys, k + 1) * t);
    }
    return out;
}

/**
 * Monotone cubic Hermite (Fritsch-Carlson), sampled at every integer.
 *
 * A plain cubic overshoots at the ends of the long gaps and sends the mace
 * briefly backwards, which reads as a stutter. This one cannot, by
 * construction. Outside the measured range it holds the end value rather than
 * extrapolating off into nothing.
 */
export function monotoneFit(xs: readonly number[], ys: readonly number[], count: number): number[] {
    const size = xs.length;
    const slopes: number[] = [];
    for (let i = 0; i < size - 1; i++) {
        slopes.push((numberAt(ys, i + 1) - numberAt(ys, i)) / (numberAt(xs, i + 1) - numberAt(xs, i)));
    }
    const tangents = new Array<number>(size).fill(0);
    tangents[0] = slopes.length > 0 ? numberAt(slopes, 0) : 0;
    tangents[size - 1] = slopes.length > 0 ? numberAt(slopes, size - 2) : 0;
    for (let i = 1; i < size - 1; i++) {
        const before = numberAt(slopes, i - 1);
        const after = numberAt(slopes, i);
        tangents[i] = before * after <= 0 ? 0 : (before + after) / 2;
    }
    for (let i = 0; i < size - 1; i++) {
        const slope = numberAt(slopes, i);
        if (slope === 0) {
            tangents[i] = 0;
            tangents[i + 1] = 0;
            continue;
        }
        const alpha = numberAt(tangents, i) / slope;
        const beta = numberAt(tangents, i + 1) / slope;
        const magnitude = Math.hypot(alpha, beta);
        if (magnitude > 3) {
            tangents[i] = (3 / magnitude) * alpha * slope;
            tangents[i + 1] = (3 / magnitude) * beta * slope;
        }
    }

    const out: number[] = [];
    for (let x = 0; x < count; x++) {
        if (x <= numberAt(xs, 0)) {
            out.push(numberAt(ys, 0));
            continue;
        }
        if (x >= numberAt(xs, size - 1)) {
            out.push(numberAt(ys, size - 1));
            continue;
        }
        let k = 0;
        while (k < size - 2 && numberAt(xs, k + 1) <= x) k++;
        const span = numberAt(xs, k + 1) - numberAt(xs, k);
        const t = (x - numberAt(xs, k)) / span;
        const t2 = t * t;
        const t3 = t2 * t;
        out.push(
            (2 * t3 - 3 * t2 + 1) * numberAt(ys, k) +
                (t3 - 2 * t2 + t) * span * numberAt(tangents, k) +
                (-2 * t3 + 3 * t2) * numberAt(ys, k + 1) +
                (t3 - t2) * span * numberAt(tangents, k + 1),
        );
    }
    return out;
}

/** Centred moving average, shrinking at the ends rather than padding them. */
export function smoothSeries(values: readonly number[], window: number): number[] {
    const half = Math.floor(window / 2);
    return values.map((_value, i) => {
        let sum = 0;
        let count = 0;
        for (let k = i - half; k <= i + half; k++) {
            const near = values[k];
            if (near === undefined) continue;
            sum += near;
            count++;
        }
        return count === 0 ? 0 : sum / count;
    });
}

/** The same, applied to every joint of every frame independently. */
export function smoothPoses(poses: readonly PoseFrame[], window: number): PoseFrame[] {
    const names = new Set<string>();
    for (const pose of poses) {
        for (const name of Object.keys(pose.joints ?? {})) names.add(name);
    }
    const smoothed: Joints[] = poses.map(() => ({}));
    const half = Math.floor(window / 2);
    for (const name of names) {
        for (let i = 0; i < poses.length; i++) {
            let sx = 0;
            let sy = 0;
            let sc = 0;
            let weight = 0;
            for (let k = i - half; k <= i + half; k++) {
                const joint = poses[k]?.joints?.[name];
                if (joint === undefined) continue;
                // Weighted by Vision's own confidence, which collapses on
                // exactly the frames where the limb is a blur and its
                // reported position is somewhere else entirely. An unweighted
                // mean lets those frames throw an arm across the body.
                const w = Math.max(joint[2], 0.01);
                sx += joint[0] * w;
                sy += joint[1] * w;
                sc += joint[2] * w;
                weight += w;
            }
            if (weight === 0) continue;
            const target = smoothed[i];
            if (target === undefined) continue;
            target[name] = [sx / weight, sy / weight, sc / weight];
        }
    }
    return poses.map((pose, i) => ({ file: pose.file, found: pose.found, joints: smoothed[i] ?? {} }));
}

export type Point = readonly [number, number];

export interface Figure {
    readonly joints: Record<string, Point>;
    readonly grip: Point;
    readonly maceHead: Point;
}

export interface Calibration {
    /** Where the feet sit in the footage, and how tall the standing subject
     * is there - both taken once for the whole clip, so that the figure's own
     * rise and fall survives into the drawing. */
    readonly groundX: number;
    readonly groundY: number;
    readonly standingHeight: number;
    /** How tall the figure should be, in the output's own units, and where
     * its feet land there. */
    readonly targetHeight: number;
    readonly footX: number;
    readonly footY: number;
}

function mean(values: readonly number[]): number {
    if (values.length === 0) return 0;
    return values.reduce((a, b) => a + b, 0) / values.length;
}

export function calibrate(
    poses: readonly PoseFrame[],
    targetHeight: number,
    footX: number,
    footY: number,
): Calibration {
    const ankleX: number[] = [];
    const ankleY: number[] = [];
    const heights: number[] = [];
    for (const pose of poses) {
        const joints = pose.joints;
        if (joints === undefined) continue;
        const ankle = joints["leftAnkle"] ?? joints["rightAnkle"];
        if (ankle === undefined) continue;
        ankleX.push(ankle[0]);
        ankleY.push(ankle[1]);
        const nose = joints["nose"];
        if (nose !== undefined) heights.push(ankle[1] - nose[1]);
    }
    return {
        groundX: mean(ankleX),
        groundY: mean(ankleY),
        // Standing, not average: he is shortest in the middle of the swing,
        // and an average would quietly scale that compression away.
        standingHeight: heights.length > 0 ? Math.max(...heights) : 1,
        targetHeight,
        footX,
        footY,
    };
}

function round(value: number): number {
    return Math.round(value * 10) / 10;
}

function project(x: number, y: number, cal: Calibration): Point {
    const scale = cal.targetHeight / cal.standingHeight;
    return [round((x - cal.groundX) * scale + cal.footX), round((y - cal.groundY) * scale + cal.footY)];
}

/** One drawable frame: every joint in output units, plus the two points a
 * drawn mace needs. */
export function toFigure(
    pose: PoseFrame,
    turnDegrees: number,
    radiusPixels: number,
    cal: Calibration,
): Figure | null {
    const source = pose.joints;
    if (source === undefined) return null;
    const joints: Record<string, Point> = {};
    for (const [name, value] of Object.entries(source)) {
        joints[name] = project(value[0], value[1], cal);
    }

    const wrists: Sample[] = [];
    for (const name of ["leftWrist", "rightWrist"]) {
        const wrist = source[name];
        if (wrist !== undefined) wrists.push(wrist);
    }
    const grip =
        wrists.length > 0
            ? project(mean(wrists.map((w) => w[0])), mean(wrists.map((w) => w[1])), cal)
            : [cal.footX, cal.footY - cal.targetHeight * 0.5];
    const radius = (radiusPixels * cal.targetHeight) / cal.standingHeight;
    const radians = (turnDegrees * Math.PI) / 180;
    const maceHead: Point = [
        round(grip[0] + Math.sin(radians) * radius),
        round(grip[1] - Math.cos(radians) * radius),
    ];
    return { joints, grip: [grip[0], grip[1]], maceHead };
}

// --- drawing -------------------------------------------------------------

const BONES: readonly (readonly [string, string, string])[] = [
    ["limb", "leftHip", "leftKnee"],
    ["limb", "leftKnee", "leftAnkle"],
    ["limb", "rightHip", "rightKnee"],
    ["limb", "rightKnee", "rightAnkle"],
    ["arm", "leftShoulder", "leftElbow"],
    ["arm", "leftElbow", "leftWrist"],
    ["arm", "rightShoulder", "rightElbow"],
    ["arm", "rightElbow", "rightWrist"],
];

function fmt(value: number): string {
    return String(round(value));
}

/**
 * One figure, drawn the way the rest of the page draws: ash limbs, chalk
 * arms, and a brass head on a chalk shaft in a pit-coloured casing so it
 * stays legible where it crosses the body.
 *
 * The trunk is a tapered quad built across the neck-to-root axis rather than
 * a polygon through the four shoulder and hip joints. Side-on, those four
 * points sit almost on top of each other, and a polygon through them
 * collapses into a sliver.
 */
export function drawFigure(figure: Figure, height: number): string {
    const { joints, grip, maceHead } = figure;
    const parts: string[] = [];

    const neck = joints["neck"];
    const root = joints["root"];
    if (neck !== undefined && root !== undefined) {
        const dx = root[0] - neck[0];
        const dy = root[1] - neck[1];
        const length = Math.hypot(dx, dy);
        const px = length === 0 ? 1 : -dy / length;
        const py = length === 0 ? 0 : dx / length;
        const top = height * 0.085;
        const bottom = height * 0.068;
        parts.push(
            `<path class="trunk" d="M${fmt(neck[0] + px * top)} ${fmt(neck[1] + py * top)}` +
                `L${fmt(root[0] + px * bottom)} ${fmt(root[1] + py * bottom)}` +
                `L${fmt(root[0] - px * bottom)} ${fmt(root[1] - py * bottom)}` +
                `L${fmt(neck[0] - px * top)} ${fmt(neck[1] - py * top)}Z"/>`,
        );
    }

    const nose = joints["nose"];
    if (neck !== undefined && nose !== undefined) {
        // The skull sits past the nose along the neck-to-nose line, which
        // keeps it attached when he tips his head back to watch the mace.
        const cx = neck[0] + (nose[0] - neck[0]) * 1.12;
        const cy = neck[1] + (nose[1] - neck[1]) * 1.12;
        const r = Math.max(height * 0.072, Math.hypot(nose[0] - neck[0], nose[1] - neck[1]) * 0.75);
        parts.push(`<circle class="trunk" cx="${fmt(cx)}" cy="${fmt(cy)}" r="${fmt(r)}"/>`);
    }

    for (const [cls, from, to] of BONES) {
        const a = joints[from];
        const b = joints[to];
        if (a === undefined || b === undefined) continue;
        parts.push(`<path class="${cls}" d="M${fmt(a[0])} ${fmt(a[1])}L${fmt(b[0])} ${fmt(b[1])}"/>`);
    }

    const shaft = `M${fmt(grip[0])} ${fmt(grip[1])}L${fmt(maceHead[0])} ${fmt(maceHead[1])}`;
    parts.push(`<path class="case" d="${shaft}"/>`);
    parts.push(`<path class="shaft" d="${shaft}"/>`);
    parts.push(`<circle class="head" cx="${fmt(maceHead[0])}" cy="${fmt(maceHead[1])}" r="${fmt(height * 0.05)}"/>`);
    return parts.join("");
}

export interface StripOptions {
    readonly width: number;
    readonly height: number;
    readonly figureHeight: number;
    readonly groundY: number;
    readonly label: string;
    readonly indent: string;
}

/**
 * The whole animation as one element: every frame drawn side by side in a
 * strip, with a one-frame-wide window over it. Stepping the strip sideways is
 * a single animation for the entire figure, and it is the same trick the
 * watch screens use to roll a digit.
 */
export function renderSwingStrip(figures: readonly Figure[], options: StripOptions): string {
    const { width, height, figureHeight, groundY, label, indent } = options;
    const lines = [
        `<svg class="swinger" viewBox="0 0 ${String(width)} ${String(height)}" role="img"`,
        `     aria-label="${label}">`,
        `  <line class="ground" x1="${fmt(width * 0.2)}" y1="${fmt(groundY)}" x2="${fmt(width * 0.8)}" y2="${fmt(groundY)}"/>`,
        `  <clipPath id="swing-window"><rect width="${String(width)}" height="${String(height)}"/></clipPath>`,
        `  <g clip-path="url(#swing-window)">`,
        `    <g class="strip">`,
        ...figures.map(
            (figure, i) =>
                `      <g transform="translate(${String(i * width)} 0)">${drawFigure(figure, figureHeight)}</g>`,
        ),
        `    </g>`,
        `  </g>`,
        `</svg>`,
    ];
    return lines.map((line) => indent + line).join("\n");
}
