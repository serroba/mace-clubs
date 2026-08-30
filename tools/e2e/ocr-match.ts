// OCR-tolerant screen assertions.
//
// These tests ask "is the app in the expected state", and answer it by
// reading the screen. An exact substring match is the wrong tool for that:
// OCR gets a character wrong now and then, and it does so differently per
// device, because the font rasterizer differs. Real examples from a single
// run of the same test files:
//
//   fenix7   "Side: Two-handed"  -> "*ide: Two-handed"
//   venu3    "Discard & go home" -> "biscard & go hom"
//
// Nothing is wrong with the app in either case, but `/Side/i` and
// `/Discard/i` both fail. Weakening each assertion to whichever substring
// happened to survive would be worse than the disease - the assertions would
// stop saying what they mean, and would drift further with every new device.
//
// So the matching, not the assertion, absorbs the noise: each word of the
// expected phrase has to appear in the OCR output within an edit distance of
// one (for words long enough that one substitution is clearly noise rather
// than a different word). A genuinely wrong screen still fails, because it
// will not contain those words at all.

/** Words this short must match exactly - at 3 characters or fewer, one edit
 * away is a different word ("hr" and "up", "set" and "sit"). */
const FUZZY_MIN_LENGTH = 4;

function normalize(text: string): string[] {
    return text
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, " ")
        .split(/\s+/)
        .filter((word) => word.length > 0);
}

/** Levenshtein distance, capped - we only ever care whether it exceeds 1. */
function withinOneEdit(a: string, b: string): boolean {
    if (a === b) {
        return true;
    }
    if (Math.abs(a.length - b.length) > 1) {
        return false;
    }
    // One substitution, insertion, or deletion.
    let i = 0;
    let j = 0;
    let edits = 0;
    while (i < a.length && j < b.length) {
        if (a[i] === b[j]) {
            i += 1;
            j += 1;
            continue;
        }
        edits += 1;
        if (edits > 1) {
            return false;
        }
        if (a.length > b.length) {
            i += 1;
        } else if (a.length < b.length) {
            j += 1;
        } else {
            i += 1;
            j += 1;
        }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
}

function wordAppears(haystack: string[], word: string): boolean {
    if (word.length < FUZZY_MIN_LENGTH) {
        return haystack.includes(word);
    }
    return haystack.some((candidate) => withinOneEdit(candidate, word));
}

/** Accepts either readText()'s lines or an already-joined string, so a test
 * can pass whichever reads better at the call site. */
export type Screen = string | string[];

function joinScreen(screen: Screen): string {
    return typeof screen === "string" ? screen : screen.join(" ");
}

/** Does the OCR output contain every word of `phrase`, allowing one wrong
 * character per word? */
export function screenShows(screen: Screen, phrase: string): boolean {
    const haystack = normalize(joinScreen(screen));
    const words = normalize(phrase);
    if (words.every((word) => wordAppears(haystack, word))) {
        return true;
    }
    // OCR also loses the space *between* words: Tesseract read "BACK exit" as
    // one "_BACKexit" token on fenix7, which no per-word check can match
    // because the token is neither word. Fall back to comparing with all
    // whitespace removed. Exact rather than fuzzy - this is an extra way to
    // pass, and a run of concatenated words is long enough that demanding an
    // exact match still means something.
    return haystack.join("").includes(words.join(""));
}

export function assertScreenShows(screen: Screen, phrase: string, context?: string): void {
    if (!screenShows(screen, phrase)) {
        const where = context === undefined ? "" : ` (${context})`;
        throw new Error(`expected "${phrase}" on screen${where}, but read: ${JSON.stringify(joinScreen(screen))}`);
    }
}

export function assertScreenLacks(screen: Screen, phrase: string, context?: string): void {
    if (screenShows(screen, phrase)) {
        const where = context === undefined ? "" : ` (${context})`;
        throw new Error(
            `did not expect "${phrase}" on screen${where}, but read: ${JSON.stringify(joinScreen(screen))}`,
        );
    }
}
