// The OCR line assembly that keeps the Linux driver's readText() to one line
// per row of the screen, in screen order rather than in the order its passes
// happened to finish.
//
// Unit-tested rather than left to the e2e suite because the failure it guards
// against does not look like a failure: rest-screen.e2e.test.ts finds the big
// countdown by reading the value directly *before* the "SELECT: work" label,
// so a line delivered out of position - or a second, worse reading of a row
// inserted beside it - makes that test report a wall-clock regression against
// a screen drawing correctly. It did exactly that twice, on devices whoever
// reads CI is unlikely to own.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { mergeByPosition, parseTsvLines } from "./e2e/platform-linux.ts";

// level page block par line word left top width height conf text
const HEADER = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext";

function word(
    { block = 1, par = 1, line = 1, left = 10, top = 40, conf = 96 },
    index: number,
    text: string,
): string {
    return ["5", "1", String(block), String(par), String(line), String(index), String(left), String(top), "40", "20", String(conf), text].join(
        "\t",
    );
}

void describe("parseTsvLines", () => {
    it("joins words sharing a block/paragraph/line into one line", () => {
        const tsv = [HEADER, word({}, 1, "REST"), word({ left: 60 }, 2, "7:28"), word({ left: 110 }, 3, "pm")].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 100), [{ text: "REST 7:28 pm", top: 40, confidence: 96 }]);
    });

    it("keeps separate lines separate, and takes each line's topmost word", () => {
        const tsv = [
            HEADER,
            word({ line: 1, top: 40 }, 1, "REST"),
            word({ line: 2, top: 90 }, 1, "0:01"),
            // A word nudged a pixel high must not drag the line above its peers.
            word({ line: 2, top: 88, left: 60 }, 2, "left"),
        ].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 100), [
            { text: "REST", top: 40, confidence: 96 },
            { text: "0:01 left", top: 88, confidence: 96 },
        ]);
    });

    it("normalises coordinates back through the pass's upscale factor", () => {
        // The same row read at 400% reports a top four times larger; both
        // passes have to agree on where the row is or the merge cannot sort.
        const tsv = [HEADER, word({ top: 160 }, 1, "REST")].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 400), [{ text: "REST", top: 40, confidence: 96 }]);
    });

    it("drops words Tesseract is not confident about", () => {
        // The inverted pass hallucinates these off Menu2's highlighted row:
        // "Lt}", "eh 0", "PO 4" all appeared in a single CI run.
        const tsv = [HEADER, word({ conf: 12 }, 1, "Lt}"), word({ line: 2, top: 90, conf: 91 }, 1, "REST")].join("\n");
        assert.deepEqual(parseTsvLines(tsv, 100), [{ text: "REST", top: 90, confidence: 91 }]);
    });

    it("ignores Tesseract's structural rows and empty text", () => {
        const structural = ["4", "1", "1", "1", "1", "0", "10", "40", "40", "20", "-1", ""].join("\t");
        const blank = word({ line: 2, top: 90 }, 1, "   ");
        assert.deepEqual(parseTsvLines([HEADER, structural, blank, word({ line: 3, top: 120 }, 1, "REST")].join("\n"), 100), [
            { text: "REST", top: 120, confidence: 96 },
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
        // the countdown, and the 200% pass reads only the countdown, because
        // it is the largest text on the screen. The countdown has to land
        // between them, not after them.
        const merged = mergeByPosition([
            { text: "- 0:01 -", top: 10, confidence: 90 },
            { text: "REST 7:28 pm", top: 40, confidence: 90 },
            { text: "SELECT: work", top: 150, confidence: 90 },
            { text: "3:21", top: 90, confidence: 90 },
        ]);
        assert.deepEqual(merged, ["- 0:01 -", "REST 7:28 pm", "3:21", "SELECT: work"]);
        // Which is the whole point: the value before the label is the
        // countdown, and it differs from the wall clock on row 2.
        assert.equal(merged[merged.indexOf("SELECT: work") - 1], "3:21");
    });

    it("collapses a row several passes read differently, keeping the surest reading", () => {
        // Verbatim from a CI run on instinct3solar45mm, where both readings
        // survived and pushed the countdown away from its label.
        const merged = mergeByPosition([
            { text: "REST 7:50} 1", top: 40, confidence: 71 },
            { text: "REST 7:50, 1", top: 42, confidence: 83 },
            { text: "0:00", top: 90, confidence: 88 },
            { text: "SELECT: work", top: 150, confidence: 92 },
        ]);
        assert.deepEqual(merged, ["REST 7:50, 1", "0:00", "SELECT: work"]);
        assert.equal(merged[merged.indexOf("SELECT: work") - 1], "0:00");
    });

    it("keeps rows that are close but genuinely distinct", () => {
        // Two footer labels a few pixels apart are still two rows; the
        // tolerance has to be tighter than the gap between real rows.
        const merged = mergeByPosition([
            { text: "sets", top: 100, confidence: 90 },
            { text: "rnds", top: 120, confidence: 90 },
        ]);
        assert.deepEqual(merged, ["sets", "rnds"]);
    });

    it("returns nothing for no lines", () => {
        assert.deepEqual(mergeByPosition([]), []);
    });
});
