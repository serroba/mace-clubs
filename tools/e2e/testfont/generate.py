#!/usr/bin/env python3
"""Generates a BMFont-format bitmap font (.fnt + PNG glyph atlas) from an
open-source TrueType font, for the CI-only :testFont build variant (see
tools/e2e/testfont/README.md). Garmin's own device fonts can't legally be
redistributed (SDK EULA) and aren't present on a bare Linux CI runner, and
the simulator fatally crashes ("Invalid Font Specified") the instant an
app-drawn onUpdate() calls dc.drawText() with a missing device font - so
this bundles a real, legally-redistributable font instead.

Output format matches Garmin's own bundled sample (Analog's
blackdiamond.fnt): a single fixed-alpha channel duplicated across R/G/B/A,
declared via <font filename="..."/> in resources.xml and loaded with
WatchUi.loadResource() as a FontResource. Confirmed against
$SDK/samples/Analog/resources/resource/fonts/blackdiamond.fnt and
$SDK/bin/resources.xsd's fontType.

Usage: fontenv/bin/python3 generate.py
(fontenv is a scratch venv - see README.md; not committed).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/Users/sebastian/Library/Fonts/JetBrainsMono-Regular.ttf"
FONT_SIZE_PX = 22
OUT_DIR = Path(__file__).resolve().parent.parent.parent.parent / "resources-testfont" / "fonts"
FONT_ID = "id_font_testfont"
FNT_NAME = "testfont.fnt"
PNG_NAME = "testfont_0.png"

# Printable ASCII - covers everything drawn on screen (labels, numbers,
# units) without needing to enumerate exact strings per view.
CHARSET = [chr(c) for c in range(0x20, 0x7F)]

CELL_W = 18
CELL_H = 30
COLS = 14
PADDING = 1


def cell_origin(index: int) -> tuple[int, int]:
    row, col = divmod(index, COLS)
    return col * CELL_W, row * CELL_H


def main() -> None:
    rows = (len(CHARSET) + COLS - 1) // COLS
    scale_w = COLS * CELL_W
    scale_h = rows * CELL_H

    # Single-channel 8-bit grayscale, matching Garmin's own How_Do_I_Use_
    # Custom_Fonts.html ("the font's PNG is a grayscale image and therefore
    # has only one channel") and blackdiamond_0.png's actual encoding
    # (confirmed via `file`: "256 x 256, 8-bit grayscale"). An RGBA atlas
    # compiles fine but the resource fails at runtime with a native
    # "Invalid Font Specified" crash with no Monkey C stack frame.
    coverage = Image.new("L", (scale_w, scale_h), 0)
    draw = ImageDraw.Draw(coverage)
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE_PX)

    ascent, descent = font.getmetrics()
    line_height = ascent + descent
    base = ascent

    chars: list[str] = []
    for i, ch in enumerate(CHARSET):
        ox, oy = cell_origin(i)
        bbox = draw.textbbox((0, 0), ch, font=font)
        left, top, right, bottom = bbox
        w = max(right - left, 1)
        h = max(bottom - top, 1)
        draw.text((ox + PADDING - left, oy + PADDING - top), ch, font=font, fill=255)
        advance = font.getlength(ch)
        chars.append(
            f'char id={ord(ch):<5}x={ox + PADDING:<5}y={oy + PADDING:<5}'
            f'width={w:<5}height={h:<5}xoffset={left:<5}yoffset={top + PADDING:<5}'
            f'xadvance={round(advance):<5}page=0  chnl=15'
        )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png_path = OUT_DIR / PNG_NAME
    coverage.save(png_path)

    fnt_lines = [
        f'info face="JetBrains Mono (test-only)" size={FONT_SIZE_PX} bold=0 italic=0 '
        f'charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={line_height} base={base} scaleW={scale_w} scaleH={scale_h} "
        f"pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{PNG_NAME}"',
        f"chars count={len(chars)}",
        *chars,
    ]
    fnt_path = OUT_DIR / FNT_NAME
    fnt_path.write_text("\n".join(fnt_lines) + "\n")

    print(f"wrote {fnt_path} ({len(chars)} glyphs, {scale_w}x{scale_h} atlas)")
    print(f"wrote {png_path}")

    preview = OUT_DIR.parent.parent / "tools" / "e2e" / "testfont" / "preview.png"
    subprocess.run(["cp", str(png_path), str(preview)], check=False)


if __name__ == "__main__":
    main()
