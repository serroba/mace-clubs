// The OCR line assembly that keeps the Linux driver's readText() in screen
// order rather than in the order its passes happened to finish.
//
// This is unit-tested rather than left to the e2e suite because the failure
// it guards against does not look like a failure: rest-screen.e2e.test.ts
// finds the big countdown by reading the value directly *before* the
// "SELECT: work" label, so a line delivered out of position makes that test
// report a wall-clock regression against a screen that is drawing correctly.
// That happened twice on a 240px Forerunner 945, where the countdown is the
// one row only the 200% pass can read.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { mergeByPosition, parseTsvLines } from "./e2e/platform-linux.ts";

// level page block par line word left top width height conf text
const HEADER = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext";

function word(block: number, par: number, line: number, w: number, left: number, top: number, text: string): string {
    return ["5", "1", String(block), String(par), String(line), String(w), String(left), String(top), "40", "20", "96", text].join("\t");
}

void describe("parseTsvLines", () => {
    it("joins words sharing a block/paragraph/line into one line", () => {
        const tsv = [HEADER, word(1, 1, 1, 1, 10, 40, "REST"), word(1, 1, 1, 2, 60, 40, "7:28"), word(1, 1, 1, 3, 110, 40, "pm")].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 100), [{ text: "REST 7:28 pm", top: 40 }]);
    });

    it("keeps separate lines separate, and takes each line's topmost word", () => {
        const tsv = [
            HEADER,
            word(1, 1, 1, 1, 10, 40, "REST"),
            word(1, 1, 2, 1, 10, 90, "0:01"),
            // A word nudged a pixel high must not drag the line above its peers.
            word(1, 1, 2, 2, 60, 88, "left"),
        ].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 100), [
            { text: "REST", top: 40 },
            { text: "0:01 left", top: 88 },
        ]);
    });

    it("normalises coordinates back through the pass's upscale factor", () => {
        // The same row read at 400% reports a top four times larger; both
        // passes have to agree on where the row is or the merge cannot sort.
        const tsv = [HEADER, word(1, 1, 1, 1, 40, 160, "REST")].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 400), [{ text: "REST", top: 40 }]);
    });

    it("ignores Tesseract's structural rows and empty text", () => {
        const structural = ["4", "1", "1", "1", "1", "0", "10", "40", "40", "20", "-1", ""].join("\t");
        const blank = word(1, 1, 2, 1, 10, 90, "   ");
        assert.deepEqual(parseTsvLines([HEADER, structural, blank, word(1, 1, 3, 1, 10, 120, "REST")].join("\n"), 100), [
            { text: "REST", top: 120 },
        ]);
    });

    it("survives output with no words at all", () => {
        assert.deepEqual(parseTsvLines(HEADER, 100), []);
        assert.deepEqual(parseTsvLines("", 100), []);
    });
});

void describe("mergeByPosition", () => {
    it("orders every pass's lines top to bottom, not pass by pass", () => {
        // The Forerunner 945 rest screen: the 400% pass reads everything but
        // the countdown, and the 200% pass reads only the countdown. The
        // countdown has to land between them, not after them.
        const merged = mergeByPosition([
            { text: "- 0:01 -", top: 10 },
            { text: "REST 7:28 pm", top: 40 },
            { text: "SELECT: work", top: 150 },
            { text: "3:21", top: 90 },
        ]);
        assert.deepEqual(merged, ["- 0:01 -", "REST 7:28 pm", "3:21", "SELECT: work"]);
        // Which is the whole point: the value before the label is the
        // countdown, and it differs from the wall clock on row 2.
        assert.equal(merged[merged.indexOf("SELECT: work") - 1], "3:21");
    });

    it("reports a row seen by several passes once, at the position they agree on", () => {
        const merged = mergeByPosition([
            { text: "REST", top: 41 },
            { text: "SELECT: work", top: 150 },
            { text: "REST", top: 40 },
        ]);
        assert.deepEqual(merged, ["REST", "SELECT: work"]);
    });

    it("breaks ties on first sighting, so equal heights keep the leading pass's order", () => {
        assert.deepEqual(
            mergeByPosition([
                { text: "left", top: 40 },
                { text: "right", top: 40 },
            ]),
            ["left", "right"],
        );
    });

    it("returns nothing for no lines", () => {
        assert.deepEqual(mergeByPosition([]), []);
    });
});
