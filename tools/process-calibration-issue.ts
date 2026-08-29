#!/usr/bin/env node
// Turns a "Calibration recording" issue
// (.github/ISSUE_TEMPLATE/calibration-recording.yml) into either a rejection
// reason or a new tools/fixtures/index.json unlabelledFixtures entry, plus a
// copied FIT file and two review aids: the full interactive report
// (report-fit.ts's render(), for a local deep-dive) and a small static SVG +
// markdown table comparing on-device detected swings against the
// contributor's claimed real count (for an inline PR/comment preview - see
// tools/calibration-preview-svg.ts).
//
// Called by .github/workflows/calibration-intake.yml; see
// CONTRIBUTING.md#calibration-recordings for the human-facing side, and
// docs/swing-counting.md for why community submissions land as *unlabelled*
// (self-reported ground truth, not promoted to the trusted `fixtures` array
// without a maintainer's deliberate review).
//
// Usage:
//   node --experimental-strip-types tools/process-calibration-issue.ts \
//     --body-file issue-body.txt --issue-number 42 \
//     --issue-url https://github.com/owner/repo/issues/42
//
// Prints one JSON object to stdout: {status: "pass", ...} or {status: "fail", reasons: [...]}.

import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { renderCalibrationPreviewSvg, renderCalibrationPreviewTable } from "./calibration-preview-svg.ts";
import { fitPath, messagesOf, numberField, readFit } from "./fit-io.ts";
import { collect, render } from "./report-fit.ts";
import { validate } from "./validate-workout.ts";

const FIXTURES_DIR = fileURLToPath(new URL("fixtures", import.meta.url));
const MAX_DOWNLOAD_BYTES = 5 * 1024 * 1024;

const EQUIPMENT_LABEL = "Equipment";
const WEIGHT_LABEL = "Equipment weight (grams, per implement)";
const MOVEMENT_LABEL = "Movement";
const DEBUG_LABEL = 'Was "Swing calibration logging" enabled for this recording?';
const COUNTS_LABEL = "Real per-set swing counts";
const NOTES_LABEL = "Anything else?";
const CONSENT_LABEL = "Before you submit";
const CONSENT_NO_LOCATION = "no GPS/location data";
const CONSENT_PUBLISH = "published in this public repo";

interface Fields {
    equipment: string | null;
    equipmentWeightGrams: number | null;
    movement: string | null;
    swingDebugEnabled: boolean | null;
    claimedRealSwingsPerSet: number[] | null;
    notes: string;
    consentNoLocation: boolean;
    consentPublish: boolean;
}

function parseSections(body: string): Map<string, string> {
    const sections = new Map<string, string>();
    for (const part of body.split(/\n(?=### )/g)) {
        const match = /^### (.+?)\n\n?([\s\S]*)$/.exec(part.trim());
        if (match?.[1] !== undefined) {
            sections.set(match[1].trim(), (match[2] ?? "").trim());
        }
    }
    return sections;
}

function isChecked(sectionText: string, optionLabelFragment: string): boolean {
    const line = sectionText.split("\n").find((candidate) => candidate.includes(optionLabelFragment));
    return line !== undefined && /^-\s*\[[xX]\]/.test(line.trim());
}

function parseNumberList(text: string): number[] | null {
    const numbers = text
        .split(/[,\n]/)
        .map((piece) => piece.trim())
        .filter((piece) => piece.length > 0)
        .map((piece) => Number(piece));
    if (numbers.length === 0 || numbers.some((n) => !Number.isFinite(n) || n < 0 || !Number.isInteger(n))) {
        return null;
    }
    return numbers;
}

function parseFields(body: string): Fields {
    const sections = parseSections(body);
    const weightText = sections.get(WEIGHT_LABEL);
    const debugText = sections.get(DEBUG_LABEL);
    const countsText = sections.get(COUNTS_LABEL);
    const consentSection = sections.get(CONSENT_LABEL) ?? "";
    return {
        equipment: sections.get(EQUIPMENT_LABEL) ?? null,
        equipmentWeightGrams:
            weightText !== undefined && weightText !== "" && Number.isFinite(Number(weightText))
                ? Number(weightText)
                : null,
        movement: sections.get(MOVEMENT_LABEL) ?? null,
        swingDebugEnabled: debugText === undefined ? null : debugText.toLowerCase().startsWith("yes"),
        claimedRealSwingsPerSet: countsText !== undefined ? parseNumberList(countsText) : null,
        notes: sections.get(NOTES_LABEL) ?? "",
        consentNoLocation: isChecked(consentSection, CONSENT_NO_LOCATION),
        consentPublish: isChecked(consentSection, CONSENT_PUBLISH),
    };
}

function findAttachmentUrl(body: string): string | null {
    const match = /https:\/\/github\.com\/user-attachments\/files\/\S+/.exec(body);
    return match !== null ? match[0].replace(/[).,]+$/, "") : null;
}

const POSITION_FIELDS = ["position_lat", "position_long", "start_position_lat", "start_position_long"];

function findsLocationData(fit: ReturnType<typeof readFit>): boolean {
    for (const messageType of ["recordMesgs", "sessionMesgs", "lapMesgs"] as const) {
        for (const mesg of messagesOf(fit, messageType)) {
            for (const field of POSITION_FIELDS) {
                if (numberField(fit, mesg, field) !== null) {
                    return true;
                }
            }
        }
    }
    return false;
}

interface CliArgs {
    bodyFile: string;
    issueNumber: string;
    issueUrl: string;
}

function parseArgs(argv: readonly string[]): CliArgs {
    const args: Record<keyof CliArgs, string | undefined> = {
        bodyFile: undefined,
        issueNumber: undefined,
        issueUrl: undefined,
    };
    for (let i = 0; i < argv.length; i += 1) {
        const flag = argv[i];
        const value = argv[i + 1];
        if (flag === "--body-file") {
            args.bodyFile = value;
        } else if (flag === "--issue-number") {
            args.issueNumber = value;
        } else if (flag === "--issue-url") {
            args.issueUrl = value;
        }
        i += 1;
    }
    if (args.bodyFile === undefined || args.issueNumber === undefined || args.issueUrl === undefined) {
        throw new Error("usage: process-calibration-issue.ts --body-file F --issue-number N --issue-url URL");
    }
    return { bodyFile: args.bodyFile, issueNumber: args.issueNumber, issueUrl: args.issueUrl };
}

async function downloadAttachment(url: string, destination: string): Promise<void> {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`download failed: HTTP ${String(response.status)}`);
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.byteLength > MAX_DOWNLOAD_BYTES) {
        throw new Error(`attachment is ${String(buffer.byteLength)} bytes, over the ${String(MAX_DOWNLOAD_BYTES)} limit`);
    }
    writeFileSync(destination, buffer);
}

async function main(): Promise<void> {
    const args = parseArgs(process.argv.slice(2));
    const body = readFileSync(args.bodyFile, "utf8");
    const fields = parseFields(body);
    const reasons: string[] = [];

    if (fields.equipment === null || fields.equipment === "") {
        reasons.push("Equipment field is missing.");
    }
    if (fields.movement === null || fields.movement === "") {
        reasons.push("Movement field is missing.");
    }
    if (fields.claimedRealSwingsPerSet === null) {
        reasons.push('"Real per-set swing counts" must be a comma or newline separated list of non-negative whole numbers.');
    }
    if (!fields.consentNoLocation) {
        reasons.push('The "no GPS/location data" checkbox is not checked.');
    }
    if (!fields.consentPublish) {
        reasons.push('The "okay with this being published" checkbox is not checked.');
    }

    const attachmentUrl = findAttachmentUrl(body);
    if (attachmentUrl === null) {
        reasons.push("No file attachment found in the issue body - attach your FIT file (or a .zip of it) by dragging it into a text field.");
    }

    if (reasons.length > 0 || attachmentUrl === null) {
        console.log(JSON.stringify({ status: "fail", reasons }));
        return;
    }

    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-calibration-"));
    try {
        const downloadName = decodeURIComponent(attachmentUrl.split("/").pop() ?? "upload");
        const downloadPath = join(temporary, downloadName);
        await downloadAttachment(attachmentUrl, downloadPath);

        let fit;
        try {
            fit = readFit(readFileSync(fitPath(downloadPath, temporary)));
        } catch (error) {
            console.log(
                JSON.stringify({
                    status: "fail",
                    reasons: [`Could not decode the attachment as a FIT file (or a .zip containing one): ${String(error)}`],
                }),
            );
            return;
        }

        if (findsLocationData(fit)) {
            console.log(
                JSON.stringify({
                    status: "fail",
                    reasons: [
                        "This recording appears to include GPS/location data (position_lat/position_long fields). " +
                            "We don't accept location data - please re-record with location tracking off, or strip " +
                            "those fields, and resubmit.",
                    ],
                }),
            );
            return;
        }

        const report = collect(fit);
        const quality = validate(report);
        const onDeviceDetectedPerSet = report.laps
            .filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0)
            .map((lap) => lap.swings ?? 0);

        // A strict "invalid" validate() status alone isn't disqualifying -
        // one of this repo's own trusted tuning fixtures (recC) trips the
        // same bar (a single implausible cadence sample near a set
        // boundary) and is still useful. Only block when there's nothing to
        // review at all; surface real findings as a caveat for the human
        // reviewer instead of an automated rejection.
        if (onDeviceDetectedPerSet.length === 0) {
            console.log(
                JSON.stringify({
                    status: "fail",
                    reasons: [
                        "No work sets were found in this recording - there's nothing to compare your claimed counts against.",
                        ...quality.findings.filter((f) => f.severity === "error").map((f) => f.message),
                    ],
                }),
            );
            return;
        }

        const fixtureId = `community-${args.issueNumber}`;
        const fixtureFileName = `${fixtureId}.fit`;
        copyFileSync(fitPath(downloadPath, temporary), join(FIXTURES_DIR, fixtureFileName));

        // Written straight into tools/fixtures/ (not a separate temp dir) so
        // the calling workflow can open a PR from "everything git now sees
        // as changed" without a manual copy step.
        const previewSvgPath = join(FIXTURES_DIR, `${fixtureId}-preview.svg`);
        writeFileSync(
            previewSvgPath,
            renderCalibrationPreviewSvg(onDeviceDetectedPerSet, fields.claimedRealSwingsPerSet),
        );
        const previewTable = renderCalibrationPreviewTable(onDeviceDetectedPerSet, fields.claimedRealSwingsPerSet);
        const reportHtmlPath = join(FIXTURES_DIR, `${fixtureId}-report.html`);
        writeFileSync(reportHtmlPath, render(report, `Community calibration #${args.issueNumber}`));

        const indexPath = join(FIXTURES_DIR, "index.json");
        const index = JSON.parse(readFileSync(indexPath, "utf8")) as {
            fixtures: unknown[];
            unlabelledFixtures: Record<string, unknown>[];
        };
        const qualityCaveat =
            quality.status === "healthy"
                ? ""
                : ` Automated FIT validation flagged this as "${quality.status}": ` +
                  `${quality.findings.map((f) => f.message).join("; ")}.`;
        index.unlabelledFixtures.push({
            id: fixtureId,
            file: fixtureFileName,
            equipment: fields.equipment,
            equipmentWeightGrams: fields.equipmentWeightGrams,
            movement: fields.movement,
            swingDebugEnabled: fields.swingDebugEnabled,
            onDeviceDetectedPerSet,
            contributorClaimedRealSwingsPerSet: fields.claimedRealSwingsPerSet,
            sourceIssue: args.issueUrl,
            notes:
                `Community-contributed via ${args.issueUrl}. contributorClaimedRealSwingsPerSet is ` +
                "self-reported and not independently verified - do not use for tuning until a maintainer " +
                `reviews it and promotes it to a "fixtures" entry with a verified realSwingsPerSet.${qualityCaveat} ` +
                (fields.notes.length > 0 ? `Contributor notes: ${fields.notes}` : ""),
        });
        writeFileSync(indexPath, `${JSON.stringify(index, null, 4)}\n`);

        console.log(
            JSON.stringify({
                status: "pass",
                fixtureId,
                fixtureFileName: `tools/fixtures/${fixtureFileName}`,
                previewSvgPath: `tools/fixtures/${fixtureId}-preview.svg`,
                reportHtmlPath: `tools/fixtures/${fixtureId}-report.html`,
                previewTable,
                onDeviceDetectedPerSet,
                claimedRealSwingsPerSet: fields.claimedRealSwingsPerSet,
                validationStatus: quality.status,
                validationFindings: quality.findings.map((f) => f.message),
            }),
        );
    } catch (error) {
        console.log(JSON.stringify({ status: "fail", reasons: [`Unexpected error: ${String(error)}`] }));
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

export { downloadAttachment, findAttachmentUrl, findsLocationData, parseFields };

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    await main();
}
