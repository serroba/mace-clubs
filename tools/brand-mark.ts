// The Mace & Clubs mark, as geometry rather than as a bitmap.
//
// The mark is a mace crossed with an Indian club: the mace's ball sits
// top-right with its shaft running down to a pommel at bottom-left, and the
// club crosses it the other way, thin handle at top-left widening into its
// bulb at bottom-right.
//
// These numbers are not a redraw. They were fitted to the shipped 62x62
// launcher_icon.png by reading its opaque spans row by row and solving for the
// circle and the two tapered capsules that produce them, so re-rendering at
// 62px reproduces the original to within a pixel. The app is live and the mark
// is recognisable; the point of vectorising it is to render it *crisply* at
// other sizes and in colour, not to change what it looks like.
//
// Design space is 62x62 to match that original. Everything downstream scales.

export const DESIGN_SIZE = 62;

/** A circle: the mace's ball. */
export interface Ball {
  kind: "ball";
  x: number;
  y: number;
  r: number;
}

/**
 * A capsule whose radius eases from `ra` at one end to `rb` at the other -
 * how both the mace shaft (a slight pommel flare) and the club (handle to
 * bulb) are shaped. Ends are rounded, which is what the original's tapered
 * tips are.
 */
export interface Taper {
  kind: "taper";
  ax: number;
  ay: number;
  ra: number;
  bx: number;
  by: number;
  rb: number;
}

export type Shape = Ball | Taper;

/** The mace's ball, and the only part the colour variants accent. */
export const MACE_HEAD: Ball = { kind: "ball", x: 45.5, y: 15.4, r: 10.1 };

/** The mace's shaft, ball down to the pommel at bottom-left. */
export const MACE_SHAFT: Taper = {
  kind: "taper",
  ax: 41.9,
  ay: 20.05,
  ra: 2.1,
  bx: 12.6,
  by: 56.0,
  rb: 3.2,
};

/** The club, thin handle top-left widening into its bulb at bottom-right. */
export const CLUB: Taper = {
  kind: "taper",
  ax: 15.7,
  ay: 10.05,
  ra: 2.4,
  bx: 46.4,
  by: 47.55,
  rb: 6.85,
};

/** Everything but the ball - the parts drawn in the mark's base colour. */
export const SHAFTS: readonly Shape[] = [CLUB, MACE_SHAFT];

/** The whole mark, as one silhouette. */
export const MARK: readonly Shape[] = [CLUB, MACE_SHAFT, MACE_HEAD];

/**
 * Signed distance to a shape in design space: negative inside, positive
 * outside, in design units. Rendering thresholds this rather than testing
 * containment, which is what gives free anti-aliasing at any scale.
 */
export function distance(shape: Shape, px: number, py: number): number {
  if (shape.kind === "ball") {
    return Math.hypot(px - shape.x, py - shape.y) - shape.r;
  }
  const dx = shape.bx - shape.ax;
  const dy = shape.by - shape.ay;
  const lengthSquared = dx * dx + dy * dy;
  const t =
    lengthSquared === 0
      ? 0
      : Math.max(
          0,
          Math.min(1, ((px - shape.ax) * dx + (py - shape.ay) * dy) / lengthSquared),
        );
  const nearestX = shape.ax + t * dx;
  const nearestY = shape.ay + t * dy;
  const radius = shape.ra + t * (shape.rb - shape.ra);
  return Math.hypot(px - nearestX, py - nearestY) - radius;
}

/** Signed distance to the union of `shapes` - the nearest surface wins. */
export function distanceToAny(shapes: readonly Shape[], px: number, py: number): number {
  let nearest = Infinity;
  for (const shape of shapes) {
    nearest = Math.min(nearest, distance(shape, px, py));
  }
  return nearest;
}

/**
 * Coverage of one pixel by `shapes`, in 0..1, from the signed distance at the
 * pixel centre. The distance is in design units, so it is converted to pixels
 * before being spread across the one-pixel band that straddles the edge.
 *
 * At the sizes this renders (26px to 1024px) that analytic edge is both
 * cheaper and cleaner than supersampling.
 */
export function coverage(
  shapes: readonly Shape[],
  px: number,
  py: number,
  designUnitsPerPixel: number,
): number {
  const d = distanceToAny(shapes, px, py) / designUnitsPerPixel;
  return Math.max(0, Math.min(1, 0.5 - d));
}

/** The mark as an SVG path-free document - circles and tapers stay readable. */
export function markSvg(options: {
  size: number;
  background?: string;
  shaftColor: string;
  headColor: string;
  cornerRadius?: number;
}): string {
  const { size, background, shaftColor, headColor, cornerRadius = 0 } = options;
  const scale = size / DESIGN_SIZE;
  // Every coordinate reaches the document through here, already a string, so
  // the SVG never inherits a float's full precision - and whole numbers stay
  // whole rather than becoming "62.000".
  const px = (n: number): string => n.toFixed(3).replace(/\.?0+$/, "");
  const s = (n: number): string => px(n * scale);

  // A taper is drawn as its two end circles plus the quadrilateral of the
  // outer tangents between them, which is exactly the capsule's hull.
  const taperPath = (t: Taper): string => {
    const length = Math.hypot(t.bx - t.ax, t.by - t.ay);
    const ux = (t.bx - t.ax) / length;
    const uy = (t.by - t.ay) / length;
    // The outer tangent leans off the perpendicular by alpha as the radius
    // grows along the capsule; at equal radii it is simply perpendicular.
    const sinAlpha = (t.ra - t.rb) / length;
    const cosAlpha = Math.sqrt(Math.max(0, 1 - sinAlpha * sinAlpha));
    // Unit directions from each centre to its tangent contact point, one per side.
    const side = (sign: number): { x: number; y: number } => ({
      x: sign * -uy * cosAlpha + ux * sinAlpha,
      y: sign * ux * cosAlpha + uy * sinAlpha,
    });
    // Walk the hull: down one tangent, back along the other, so the polygon
    // stays simple rather than crossing itself.
    const near = side(1);
    const far = side(-1);
    const quad = [
      [t.ax + t.ra * near.x, t.ay + t.ra * near.y],
      [t.bx + t.rb * near.x, t.by + t.rb * near.y],
      [t.bx + t.rb * far.x, t.by + t.rb * far.y],
      [t.ax + t.ra * far.x, t.ay + t.ra * far.y],
    ]
      .map((point) => `${s(point[0] ?? 0)},${s(point[1] ?? 0)}`)
      .join(" ");
    return (
      `<circle cx="${s(t.ax)}" cy="${s(t.ay)}" r="${s(t.ra)}"/>` +
      `<circle cx="${s(t.bx)}" cy="${s(t.by)}" r="${s(t.rb)}"/>` +
      `<polygon points="${quad}"/>`
    );
  };

  const backdrop =
    background === undefined
      ? ""
      : `<rect width="${px(size)}" height="${px(size)}" rx="${px(cornerRadius)}" fill="${background}"/>`;

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${px(size)}" height="${px(size)}" ` +
      `viewBox="0 0 ${px(size)} ${px(size)}" role="img" aria-label="Mace &amp; Clubs">`,
    backdrop,
    `<g fill="${shaftColor}">${taperPath(CLUB)}${taperPath(MACE_SHAFT)}</g>`,
    `<circle cx="${s(MACE_HEAD.x)}" cy="${s(MACE_HEAD.y)}" r="${s(MACE_HEAD.r)}" fill="${headColor}"/>`,
    `</svg>`,
    "",
  ].join("\n");
}
