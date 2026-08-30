// Unit test for the one pure function in the screenshot pipeline. The capture
// itself needs a running simulator and is exercised by `make release-shots`.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { PNG } from "pngjs";

import { downscaleToNative } from "./release-shots.ts";

function solid(width: number, height: number, colour: [number, number, number, number]): Buffer {
    const png = new PNG({ width, height });
    for (let i = 0; i < width * height; i += 1) {
        for (let channel = 0; channel < 4; channel += 1) {
            png.data[(i << 2) + channel] = colour[channel] ?? 0;
        }
    }
    return PNG.sync.write(png);
}

void describe("downscaleToNative", () => {
    it("halves a Retina 2x capture to the watch's real size", () => {
        const out = PNG.sync.read(downscaleToNative(solid(908, 908, [10, 20, 30, 255]), 454, 454));
        assert.equal(out.width, 454);
        assert.equal(out.height, 454);
        // A solid colour must survive the box filter untouched.
        assert.deepEqual([out.data[0], out.data[1], out.data[2], out.data[3]], [10, 20, 30, 255]);
    });

    it("leaves a capture that is already native alone, byte for byte", () => {
        const png = solid(176, 176, [1, 2, 3, 255]);
        assert.equal(downscaleToNative(png, 176, 176), png);
    });

    it("refuses to guess at a non-integer scale", () => {
        // 300 -> 176 is not a whole multiple; better to keep the original
        // than to invent a resampling.
        const png = solid(300, 300, [1, 2, 3, 255]);
        assert.equal(downscaleToNative(png, 176, 176), png);
    });

    it("averages rather than dropping pixels", () => {
        // A 2x2 block of one black and three white pixels must come out grey,
        // not whichever pixel a nearest-neighbour sample happened to land on.
        const png = new PNG({ width: 2, height: 2 });
        for (let i = 0; i < 4; i += 1) {
            const value = i === 0 ? 0 : 255;
            png.data[(i << 2) + 0] = value;
            png.data[(i << 2) + 1] = value;
            png.data[(i << 2) + 2] = value;
            png.data[(i << 2) + 3] = 255;
        }
        const out = PNG.sync.read(downscaleToNative(PNG.sync.write(png), 1, 1));
        assert.equal(out.data[0], 191); // (0 + 255 + 255 + 255) / 4
    });
});
