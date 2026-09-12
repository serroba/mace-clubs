import assert from "node:assert/strict";
import { test } from "node:test";

import {
    calibrate,
    drawFigure,
    monotoneFit,
    renderSwingStrip,
    smoothPoses,
    smoothSeries,
    toFigure,
    traceSwing,
    type MaceSample,
    type PoseFrame,
} from "./swing-figure.ts";

function mace(i: number, angle: number | null, radius = 200, floor = 85): MaceSample {
    if (angle === null) return { file: `f${String(i)}.jpg`, found: false };
    return { file: `f${String(i)}.jpg`, found: true, angle, radius, floor };
}

test("a turn through zero is unwrapped into one continuous descent", () => {
    // Ten degrees a frame, downwards, straight through the 360/0 boundary -
    // which is where a naive reading jumps by a full turn.
    const samples = [0, 350, 340, 330, 320].map((a, i) => mace(i, a));
    const { turn } = traceSwing(samples);
    assert.deepEqual(
        turn.map((t) => Math.round(t)),
        [0, -10, -20, -30, -40],
    );
});

test("the gap where the head is too fast to photograph is filled monotonically", () => {
    // Measured at both ends, nothing in between, which is exactly the shape
    // the real footage has.
    const samples = [mace(0, 0), mace(1, 350), mace(2, null), mace(3, null), mace(4, null), mace(5, 300), mace(6, 290)];
    const { turn } = traceSwing(samples);
    for (let i = 1; i < turn.length; i++) {
        const before = turn[i - 1];
        const after = turn[i];
        assert.ok(before !== undefined && after !== undefined);
        assert.ok(after < before, `frame ${String(i)} turned backwards: ${String(before)} then ${String(after)}`);
    }
    assert.equal(Math.round(turn[6] ?? 0), -70);
});

test("a reading that would need an impossible rate is not the mace", () => {
    // The middle sample is the cowhide rug: warm, large, and 150 degrees away
    // from where the head could possibly have got to in one frame.
    const samples = [mace(0, 0), mace(1, 350), mace(2, 200), mace(3, 330), mace(4, 320)];
    const { turn } = traceSwing(samples);
    const third = turn[2];
    assert.ok(third !== undefined);
    assert.ok(third < -10 && third > -30, `the rug was believed: ${String(third)}`);
});

test("radius is taken only from the frames the angle was believed on", () => {
    // The rejected frame carries a radius too, and it is just as wrong.
    const samples = [mace(0, 0, 200), mace(1, 350, 200), mace(2, 200, 20), mace(3, 330, 200)];
    const { radius } = traceSwing(samples);
    for (const r of radius) assert.ok(r > 150, `a rejected frame's radius leaked in: ${String(r)}`);
});

test("the monotone fit does not overshoot between its points", () => {
    const fitted = monotoneFit([0, 5, 10], [0, -50, -60], 11);
    for (let i = 1; i < fitted.length; i++) {
        const before = fitted[i - 1];
        const after = fitted[i];
        assert.ok(before !== undefined && after !== undefined);
        assert.ok(after <= before + 1e-9, `overshot at ${String(i)}`);
    }
    assert.equal(Math.round(fitted[5] ?? 0), -50);
});

test("smoothing shrinks its window at the ends rather than padding them", () => {
    // A padded window would pull the first value toward zero; this one only
    // averages what is actually there.
    assert.deepEqual(smoothSeries([10, 10, 10], 3), [10, 10, 10]);
    assert.deepEqual(smoothSeries([0, 3, 0], 3), [1.5, 1, 1.5]);
});

test("a joint Vision was unsure of is not allowed to drag the smoothed one", () => {
    const poses: PoseFrame[] = [
        { file: "a", found: true, joints: { wrist: [100, 100, 0.9] } },
        { file: "b", found: true, joints: { wrist: [400, 400, 0.01] } },
        { file: "c", found: true, joints: { wrist: [100, 100, 0.9] } },
    ];
    const smoothed = smoothPoses(poses, 3);
    const middle = smoothed[1]?.joints?.["wrist"];
    assert.ok(middle !== undefined);
    // An unweighted mean would put it at 200; the confidence says otherwise.
    assert.ok(middle[0] < 125, `the blurred frame won: ${String(middle[0])}`);
});

test("scale comes from the standing height, so the crouch survives", () => {
    // Shortest in the middle, which is him loading his knees into the swing.
    const poses: PoseFrame[] = [400, 300, 400].map((noseY, i) => ({
        file: String(i),
        found: true,
        joints: { nose: [50, noseY, 0.9], leftAnkle: [50, 700, 0.9] },
    }));
    const cal = calibrate(poses, 150, 0, 0);
    assert.equal(cal.standingHeight, 400);
    assert.equal(cal.groundY, 700);
});

test("the mace head lands at the traced angle and distance from the grip", () => {
    const pose: PoseFrame = {
        file: "a",
        found: true,
        joints: { leftWrist: [100, 500, 0.9], rightWrist: [100, 500, 0.9], leftAnkle: [100, 700, 0.9] },
    };
    const cal = calibrate([{ ...pose, joints: { ...pose.joints, nose: [100, 300, 0.9] } }], 100, 0, 0);
    // A quarter turn puts it straight out to the right of the grip.
    const figure = toFigure(pose, 90, 200, cal);
    assert.ok(figure !== null);
    assert.equal(figure.maceHead[1], figure.grip[1]);
    assert.ok(figure.maceHead[0] > figure.grip[0]);
    // The subject is 400px from nose to ankle and is drawn 100 tall, so
    // 200px of shaft comes out as 50 units of it.
    assert.equal(Math.round(figure.maceHead[0] - figure.grip[0]), 50);
});

test("the shaft's casing is laid down before the shaft itself", () => {
    // Reversed, the dark casing paints over the chalk and the mace vanishes
    // wherever it crosses the body - which is most of the revolution.
    const svg = drawFigure({ joints: {}, grip: [0, 0], maceHead: [10, 10] }, 100);
    assert.ok(svg.indexOf('class="case"') < svg.indexOf('class="shaft"'));
});

test("each frame of the strip is offset by exactly one window", () => {
    const figure = { joints: {}, grip: [0, 0] as const, maceHead: [1, 1] as const };
    const svg = renderSwingStrip([figure, figure, figure], {
        width: 120,
        height: 200,
        figureHeight: 150,
        groundY: 180,
        label: "a swing",
        indent: "",
    });
    assert.ok(svg.includes('transform="translate(0 0)"'));
    assert.ok(svg.includes('transform="translate(120 0)"'));
    assert.ok(svg.includes('transform="translate(240 0)"'));
});
