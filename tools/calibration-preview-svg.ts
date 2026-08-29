// Renders a small, static, theme-aware SVG comparing a calibration
// submission's on-device detected swings against the contributor's claimed
// real count, per work set. Pure string building (no DOM, no headless
// browser) so it can run in CI and be committed straight into a PR branch,
// then embedded via a raw.githubusercontent.com <img> link the same way
// this repo's PR template already embeds screenshots.
//
// This is a purpose-built diagnostic for calibration review, not a
// replacement for report-fit.ts's full interactive report (which needs a
// browser to draw - see its <script> - and stays the tool for a real local
// deep-dive). See docs/swing-counting.md for how calibration review fits
// together, and the dataviz skill for the palette/contrast rules this
// follows (2-series categorical: blue = on-device, orange = claimed).

const WIDTH = 640;
const HEIGHT = 320;
const MARGIN = { left: 50, right: 20, top: 40, bottom: 42 };

function escapeXml(text: string): string {
    return text
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
}

export function renderCalibrationPreviewSvg(
    onDeviceDetectedPerSet: readonly number[],
    claimedRealSwingsPerSet: readonly number[] | null,
): string {
    const setCount = Math.max(onDeviceDetectedPerSet.length, claimedRealSwingsPerSet?.length ?? 0);
    const values = [...onDeviceDetectedPerSet, ...(claimedRealSwingsPerSet ?? [])];
    const maxValue = Math.max(1, ...values);
    const plotWidth = WIDTH - MARGIN.left - MARGIN.right;
    const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom;
    const groupWidth = plotWidth / Math.max(setCount, 1);
    const barWidth = Math.min(28, groupWidth * 0.34);
    const barGap = 2;

    function barHeight(value: number): number {
        return (value / maxValue) * (plotHeight - 24);
    }

    const bars: string[] = [];
    const labels: string[] = [];
    for (let i = 0; i < setCount; i += 1) {
        const groupX = MARGIN.left + i * groupWidth + groupWidth / 2;
        const detected = onDeviceDetectedPerSet[i];
        const claimed = claimedRealSwingsPerSet?.[i];
        if (detected !== undefined) {
            const h = barHeight(detected);
            const x = groupX - barWidth - barGap / 2;
            const y = MARGIN.top + plotHeight - h;
            bars.push(
                `<rect class="bar-detected" x="${String(x)}" y="${String(y)}" width="${String(barWidth)}" height="${String(h)}" rx="4" ry="4" />`,
                `<text class="value-label" x="${String(x + barWidth / 2)}" y="${String(y - 6)}" text-anchor="middle">${String(detected)}</text>`,
            );
        }
        if (claimed !== undefined) {
            const h = barHeight(claimed);
            const x = groupX + barGap / 2;
            const y = MARGIN.top + plotHeight - h;
            bars.push(
                `<rect class="bar-claimed" x="${String(x)}" y="${String(y)}" width="${String(barWidth)}" height="${String(h)}" rx="4" ry="4" />`,
                `<text class="value-label" x="${String(x + barWidth / 2)}" y="${String(y - 6)}" text-anchor="middle">${String(claimed)}</text>`,
            );
        }
        labels.push(
            `<text class="axis-label" x="${String(groupX)}" y="${String(MARGIN.top + plotHeight + 20)}" text-anchor="middle">Set ${String(i + 1)}</text>`,
        );
    }

    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${String(WIDTH)} ${String(HEIGHT)}" role="img" aria-label="On-device detected swings versus contributor-claimed real swings, per work set">
  <style>
    .surface { fill: #fcfcfb; }
    .title, .value-label { fill: #0b0b0b; }
    .axis-label, .legend-label { fill: #52514e; }
    .baseline { stroke: #c3c2b7; }
    .bar-detected { fill: #2a78d6; }
    .bar-claimed { fill: #eb6834; }
    text { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; font-size: 12px; }
    .title { font-size: 13px; }
    @media (prefers-color-scheme: dark) {
      .surface { fill: #1a1a19; }
      .title, .value-label { fill: #ffffff; }
      .axis-label, .legend-label { fill: #c3c2b7; }
      .baseline { stroke: #383835; }
      .bar-detected { fill: #3987e5; }
      .bar-claimed { fill: #d95926; }
    }
  </style>
  <rect class="surface" x="0" y="0" width="${String(WIDTH)}" height="${String(HEIGHT)}" />
  <text class="title" x="${String(MARGIN.left)}" y="18">On-device detected vs. claimed real count, per work set</text>
  <rect class="bar-detected" x="${String(MARGIN.left)}" y="26" width="12" height="12" rx="2" ry="2" />
  <text class="legend-label" x="${String(MARGIN.left + 16)}" y="36">On-device detected</text>
  <rect class="bar-claimed" x="${String(MARGIN.left + 150)}" y="26" width="12" height="12" rx="2" ry="2" />
  <text class="legend-label" x="${String(MARGIN.left + 166)}" y="36">Claimed real count</text>
  <line class="baseline" x1="${String(MARGIN.left)}" y1="${String(MARGIN.top + plotHeight)}" x2="${String(WIDTH - MARGIN.right)}" y2="${String(MARGIN.top + plotHeight)}" />
  ${bars.join("\n  ")}
  ${labels.join("\n  ")}
</svg>
`;
}

export function renderCalibrationPreviewTable(
    onDeviceDetectedPerSet: readonly number[],
    claimedRealSwingsPerSet: readonly number[] | null,
): string {
    const setCount = Math.max(onDeviceDetectedPerSet.length, claimedRealSwingsPerSet?.length ?? 0);
    const rows = ["| Set | On-device detected | Claimed real count |", "|---|---|---|"];
    for (let i = 0; i < setCount; i += 1) {
        const detected = onDeviceDetectedPerSet[i];
        const claimed = claimedRealSwingsPerSet?.[i];
        rows.push(
            `| ${String(i + 1)} | ${detected !== undefined ? String(detected) : "—"} | ${claimed !== undefined ? String(claimed) : "—"} |`,
        );
    }
    return rows.join("\n");
}

// Guards against XML injection if this is ever extended to render
// contributor-supplied text directly into the SVG (currently only numbers
// are interpolated, but keep this available for that case).
export { escapeXml };
