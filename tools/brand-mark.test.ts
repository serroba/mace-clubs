import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { PNG } from "pngjs";
import { CLUB, DESIGN_SIZE, MACE_HEAD, MACE_SHAFT, distance, markSvg } from "./brand-mark.ts";
import { PALETTE, renderMark } from "./render-brand-assets.ts";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LAUNCHER_ICON = join(REPO_ROOT, "resources/drawables/launcher_icon.png");

const WHITE: [number, number, number, number] = [255, 255, 255, 255];

// The whole point of brand-mark.ts: it claims to be the vector form of the
// bitmap the watch actually ships. If that stops being true - because someone
// edits the geometry, or replaces the PNG - the master is no longer a master,
// and every asset rendered from it silently stops matching the app. This is
// the test that makes that failure loud.
test("the vector geometry reproduces the shipped launcher icon", () => {
  const shipped = PNG.sync.read(readFileSync(LAUNCHER_ICON));
  assert.equal(shipped.width, DESIGN_SIZE, "design space tracks the shipped icon");
  assert.equal(shipped.height, DESIGN_SIZE);

  const rendered = renderMark({ size: DESIGN_SIZE, shaft: WHITE, head: WHITE });

  let disagreeing = 0;
  for (let i = 0; i < shipped.data.length; i += 4) {
    const shippedOpaque = (shipped.data[i + 3] ?? 0) > 127;
    const renderedOpaque = (rendered.data[i + 3] ?? 0) > 127;
    if (shippedOpaque !== renderedOpaque) disagreeing += 1;
  }

  const total = DESIGN_SIZE * DESIGN_SIZE;
  const agreement = 1 - disagreeing / total;
  // The geometry was fitted to this bitmap and lands at 99.1%; the remaining
  // ~34 pixels are anti-aliasing fringe along the edges, not shape error. 98%
  // leaves room for that without leaving room for a redraw.
  assert.ok(
    agreement >= 0.98,
    `vector mark should reproduce the shipped icon; ${String(disagreeing)}/${String(total)} pixels ` +
      `disagree (${(agreement * 100).toFixed(1)}% agreement, want >= 98%)`,
  );
});

test("the mark's parts sit where the mace and club are described to be", () => {
  // Ball top-right, pommel bottom-left, club bulb bottom-right. Guards against
  // an edit that keeps the shapes valid but flips the composition.
  assert.ok(MACE_HEAD.x > DESIGN_SIZE / 2 && MACE_HEAD.y < DESIGN_SIZE / 2);
  assert.ok(MACE_SHAFT.bx < DESIGN_SIZE / 2 && MACE_SHAFT.by > DESIGN_SIZE / 2);
  assert.ok(CLUB.bx > DESIGN_SIZE / 2 && CLUB.by > DESIGN_SIZE / 2);
  // The club widens towards its bulb; the mace shaft only flares slightly.
  assert.ok(CLUB.rb > CLUB.ra * 2, "club tapers handle to bulb");
  assert.ok(MACE_SHAFT.rb > MACE_SHAFT.ra, "mace shaft flares into a pommel");
});

test("signed distance is negative inside a shape and positive outside", () => {
  assert.ok(distance(MACE_HEAD, MACE_HEAD.x, MACE_HEAD.y) < 0);
  assert.equal(
    Number(distance(MACE_HEAD, MACE_HEAD.x + MACE_HEAD.r, MACE_HEAD.y).toFixed(6)),
    0,
  );
  assert.ok(distance(MACE_HEAD, 0, DESIGN_SIZE) > 0);
  assert.ok(distance(CLUB, CLUB.ax, CLUB.ay) < 0, "inside the handle end cap");
  assert.ok(distance(CLUB, CLUB.bx, CLUB.by) < 0, "inside the bulb");
});

test("rendering scales without clipping the mark", () => {
  // A 26px launcher (the smallest device in the manifest) and a 1024px store
  // icon must both contain the whole silhouette, edges included.
  for (const size of [26, 62, 180]) {
    const png = renderMark({ size, shaft: WHITE, head: WHITE });
    const edgeOpaque = (x: number, y: number): boolean =>
      (png.data[(y * size + x) * 4 + 3] ?? 0) > 0;
    for (let i = 0; i < size; i += 1) {
      assert.ok(
        !edgeOpaque(i, 0) && !edgeOpaque(i, size - 1),
        `mark touches a horizontal edge at ${String(size)}px`,
      );
      assert.ok(
        !edgeOpaque(0, i) && !edgeOpaque(size - 1, i),
        `mark touches a vertical edge at ${String(size)}px`,
      );
    }
  }
});

test("the badge variant is opaque everywhere the store will show it", () => {
  // The bug this whole change exists to fix: a mark with no backdrop vanishes
  // on a light background. The badge must never be transparent in its middle.
  const size = 64;
  const png = renderMark({
    size,
    shaft: WHITE,
    head: WHITE,
    background: [31, 56, 45, 255],
    cornerRadius: size * 0.22,
  });
  const centre = png.data[((size / 2) * size + size / 2) * 4 + 3];
  assert.equal(centre, 255, "badge centre is fully opaque");
});

test("the SVG master carries both colours and a title", () => {
  const svg = markSvg({ size: 62, shaftColor: "#E8DCC8", headColor: "#C08A3E" });
  assert.match(svg, /<svg[^>]+viewBox="0 0 62 62"/);
  assert.match(svg, /aria-label="Mace &amp; Clubs"/);
  assert.match(svg, /#E8DCC8/);
  assert.match(svg, /#C08A3E/);
  assert.ok(!svg.includes("NaN"), "tangent maths produced finite coordinates");
});

/** The hex custom properties declared on the site's `:root`. */
function siteTokens(): Map<string, string> {
  const css = readFileSync(join(REPO_ROOT, "docs/index.html"), "utf8");
  const root = /:root\s*\{([\s\S]*?)\}/.exec(css)?.[1] ?? "";
  const tokens = new Map<string, string>();
  for (const match of root.matchAll(/--([a-z-]+):\s*(#[0-9A-Fa-f]{6})\s*;/g)) {
    tokens.set(match[1] ?? "", (match[2] ?? "").toUpperCase());
  }
  return tokens;
}

// docs/brand.md has claimed since the icon landed that its colours are "taken
// from the website's custom properties, so the icon and the page it sits on
// cannot drift apart". They drifted apart the moment the site was redressed:
// the badge stayed forest green while the page went clay and brass, and a
// green favicon sat in the tab above it. Nothing failed, because the invariant
// was only ever asserted in prose. This is the mechanism.
test("the icon palette is the site's palette", () => {
  const tokens = siteTokens();
  assert.ok(tokens.size >= 3, "should find hex custom properties on the site's :root");

  for (const [name, hex] of Object.entries(PALETTE)) {
    const onSite = tokens.get(name);
    assert.ok(
      onSite !== undefined,
      `PALETTE.${name} has no matching --${name} custom property in docs/index.html`,
    );
    assert.equal(
      hex.toUpperCase(),
      onSite,
      `PALETTE.${name} is ${hex} but the site's --${name} is ${onSite}; ` +
        "run `make brand-assets` after changing either",
    );
  }
});
