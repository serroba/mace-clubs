import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

const read = (relativePath: string): string =>
  readFileSync(join(REPO_ROOT, relativePath), "utf8");

/** Every surface that states how many watches the app runs on. */
const SURFACES = ["README.md", "docs/index.html", "docs/store-listing.md"] as const;

/** "...on 120 Connect IQ watches", however the sentence around it is phrased. */
const CLAIM = /(\d+) Connect IQ watches/g;

function manifestDeviceCount(): number {
  return read("manifest.xml").match(/<iq:product /g)?.length ?? 0;
}

// This number drifted before, and drift is the whole problem: the site claimed
// "120+ Connect IQ watches" while the README claimed the only supported watch
// was the Instinct. Whoever adds a device to the manifest is not going to
// remember three prose files, so this fails for them instead.
test("every stated device count matches the manifest", () => {
  const expected = manifestDeviceCount();
  assert.ok(expected > 0, "manifest.xml should declare products");

  for (const surface of SURFACES) {
    const matches = [...read(surface).matchAll(CLAIM)];
    assert.ok(
      matches.length > 0,
      `${surface} should state the device-support claim (see docs/brand.md)`,
    );
    for (const match of matches) {
      assert.equal(
        Number(match[1]),
        expected,
        `${surface} claims ${String(match[1])} watches; manifest.xml has ${String(expected)}`,
      );
    }
  }
});

// The count on its own overclaims - it is what made "runs on 120+ watches" and
// "the supported watch is the Instinct 3 Solar" both appear in the repo at
// once. Wherever the number appears, the validation caveat has to appear too.
test("every stated device count is qualified by where counting is validated", () => {
  for (const surface of SURFACES) {
    const text = read(surface);
    if (!CLAIM.test(text)) continue;
    CLAIM.lastIndex = 0;
    // Flattened, so a line wrap or a non-breaking space in the middle of the
    // watch's name isn't mistaken for the caveat being absent.
    const flattened = text.replace(/&nbsp;/g, " ").replace(/\s+/g, " ");
    assert.match(
      flattened,
      /Instinct 3 Solar 45 mm/,
      `${surface} states a device count without naming where swing counting is validated`,
    );
  }
});
