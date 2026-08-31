// Renders the brand assets that live outside the app bundle: the SVG master,
// the Connect IQ Store icon, and the website's favicons.
//
// Deliberately does NOT touch resources/drawables/launcher_icon.png. That
// bitmap is what the watch shows in its app list and what MaceClubsView draws
// on the start screen, both against black, where a white silhouette is already
// correct. brand-mark.test.ts pins the geometry here to that bitmap instead, so
// the two cannot drift without a test failing.
//
// Usage: make brand-assets

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PNG } from "pngjs";
import {
  DESIGN_SIZE,
  MACE_HEAD,
  SHAFTS,
  coverage,
  markSvg,
  type Shape,
} from "./brand-mark.ts";

/** The ball on its own, so the accent colour can be composited over the shafts. */
const HEAD_ONLY: readonly Shape[] = [MACE_HEAD];

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * The site's palette, copied from docs/index.html's `:root` custom properties.
 *
 * These must stay equal to the site's own tokens. They did not: the site was
 * redressed and the icon was left on the previous scheme, so a forest-green
 * favicon sat in the tab above a clay-and-brass page. brand-mark.test.ts now
 * reads the tokens out of the stylesheet and fails when the two disagree,
 * because a comment claiming they cannot drift is not a mechanism.
 */
export const PALETTE = {
  pit: "#16100B",
  chalk: "#E8DCC8",
  brass: "#C08A3E",
} as const;

type Rgba = [number, number, number, number];

const hexToRgba = (hex: string, alpha = 255): Rgba => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
  alpha,
];

/**
 * Rasterises the mark at `size`, compositing the ball over the shafts so the
 * two colours meet cleanly, over an optional rounded-rectangle backdrop.
 *
 * Returns straight (non-premultiplied) RGBA, which is what PNG wants.
 */
export function renderMark(options: {
  size: number;
  shaft: Rgba;
  head: Rgba;
  background?: Rgba;
  cornerRadius?: number;
}): PNG {
  const { size, shaft, head, background, cornerRadius = 0 } = options;
  const png = new PNG({ width: size, height: size });
  const designUnitsPerPixel = DESIGN_SIZE / size;

  // Coverage of a rounded rectangle inset to the full canvas, used for the
  // badge backdrop. Same analytic-edge trick as the mark itself.
  const backdropCoverage = (px: number, py: number): number => {
    if (background === undefined) return 0;
    const half = size / 2;
    const r = Math.min(cornerRadius, half);
    const qx = Math.abs(px - half) - (half - r);
    const qy = Math.abs(py - half) - (half - r);
    const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0));
    const d = outside + Math.min(Math.max(qx, qy), 0) - r;
    return Math.max(0, Math.min(1, 0.5 - d));
  };

  const over = (src: Rgba, srcAlpha: number, dst: Rgba): Rgba => {
    const sa = (src[3] / 255) * srcAlpha;
    const da = dst[3] / 255;
    const outA = sa + da * (1 - sa);
    if (outA === 0) return [0, 0, 0, 0];
    const channel = (i: 0 | 1 | 2): number => (src[i] * sa + dst[i] * da * (1 - sa)) / outA;
    return [channel(0), channel(1), channel(2), outA * 255];
  };

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      // Pixel centre, in design units.
      const px = (x + 0.5) * designUnitsPerPixel;
      const py = (y + 0.5) * designUnitsPerPixel;

      let pixel: Rgba = [0, 0, 0, 0];
      if (background !== undefined) {
        pixel = over(background, backdropCoverage(x + 0.5, y + 0.5), pixel);
      }
      pixel = over(shaft, coverage(SHAFTS, px, py, designUnitsPerPixel), pixel);
      pixel = over(
        head,
        coverage(HEAD_ONLY, px, py, designUnitsPerPixel),
        pixel,
      );

      const i = (y * size + x) * 4;
      png.data[i] = Math.round(pixel[0]);
      png.data[i + 1] = Math.round(pixel[1]);
      png.data[i + 2] = Math.round(pixel[2]);
      png.data[i + 3] = Math.round(pixel[3]);
    }
  }
  return png;
}

function write(relativePath: string, contents: Buffer | string): void {
  const target = join(REPO_ROOT, relativePath);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
  console.log(`wrote ${relativePath}`);
}

function main(): void {
  const pit = hexToRgba(PALETTE.pit);
  const chalk = hexToRgba(PALETTE.chalk);
  const brass = hexToRgba(PALETTE.brass);

  // The master. Monochrome, transparent: this is the mark itself, before any
  // decision about what it sits on.
  write(
    "docs/brand/mace-clubs-mark.svg",
    markSvg({
      size: DESIGN_SIZE,
      shaftColor: "currentColor",
      headColor: "currentColor",
    }),
  );

  // The badge: what goes anywhere the background is not ours to choose - the
  // Connect IQ Store's grid, a browser tab, a phone home screen. Clay ground,
  // chalk mark, brass ball, matching the site exactly.
  const badge = (size: number): PNG =>
    renderMark({
      size,
      shaft: chalk,
      head: brass,
      background: pit,
      cornerRadius: size * 0.22,
    });

  write(
    "docs/brand/mace-clubs-icon.svg",
    markSvg({
      size: DESIGN_SIZE,
      shaftColor: PALETTE.chalk,
      headColor: PALETTE.brass,
      background: PALETTE.pit,
      cornerRadius: DESIGN_SIZE * 0.22,
    }),
  );

  // 1024 is what the Connect IQ developer dashboard wants for the store icon.
  write("docs/brand/icon-1024.png", PNG.sync.write(badge(1024)));
  write("docs/brand/apple-touch-icon-180.png", PNG.sync.write(badge(180)));
  write("docs/favicon-32.png", PNG.sync.write(badge(32)));
  write(
    "docs/favicon.svg",
    markSvg({
      size: DESIGN_SIZE,
      shaftColor: PALETTE.chalk,
      headColor: PALETTE.brass,
      background: PALETTE.pit,
      cornerRadius: DESIGN_SIZE * 0.22,
    }),
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
