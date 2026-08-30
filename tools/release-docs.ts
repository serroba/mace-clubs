#!/usr/bin/env node
// Generates the release paperwork that kept going stale by hand.
//
//   make release-docs VERSION=0.15.2
//
// Writes docs/product-updates/v<version>.md from the commits since the
// previous tag, and refreshes the generated regions of docs/store-listing.md.
// The pre-push hook refuses a v* tag whose docs are missing or stale, so the
// two cannot drift apart again - which they badly had: 19 of 26 tags had no
// product-update doc at all, and the store listing still advertised the
// version before the one that had shipped.
//
// Everything here is generated, no editing step. That is a deliberate
// trade: these notes read as a structured summary of what changed rather
// than as the hand-written narrative of, say, docs/product-updates/v0.15.0.md.
// The prose in store-listing.md is *not* regenerated for that reason - only
// the parts that go stale are, between explicit markers.
//
// Two things follow from generated files living beside hand-written ones:
//
//   - Only files carrying this tool's own trailer are overwritten. The six
//     product updates that predate the generator are narrative writing, and
//     `make release-docs VERSION=0.9.0` used to replace one with a changelog.
//   - `--check <version>` reports where the committed paperwork disagrees with
//     what this file would produce, which is what the pre-push gate asks. That
//     gate used to check only that the paperwork existed, so v0.16.0 passed it
//     while still titled "Mace and Clubs" after the generator had moved on.
//
// A tagged version's date comes from the tag, not from today, or regenerating
// an old release would restamp it - which is what made bringing the archive
// forward too dangerous to do.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = fileURLToPath(new URL("..", import.meta.url));
const REPO_URL = "https://github.com/serroba/mace-clubs";

/** Paths that mean a change is visible on the watch, rather than tooling. */
const WATCH_PATHS = ["source/", "resources", "manifest.xml"];

export interface Change {
    subject: string;
    /** Squash-merge subjects end in "(#123)"; direct commits have no PR. */
    pull: number | null;
    watchFacing: boolean;
    /**
     * What to tell a user this change did, from a `Release-note:` trailer.
     * Null when the commit has none, in which case `subject` stands in and
     * the generator says so.
     */
    releaseNote: string | null;
}

function git(args: string[]): string {
    return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8" }).trim();
}

/** The tag before `version`, by version order - not by date, since a patch
 * for an older line can be tagged after a newer minor. */
export function previousTag(version: string, tags: string[]): string | null {
    const ordered = tags
        .filter((tag) => /^v\d+\.\d+\.\d+$/.test(tag))
        .sort((a, b) => compareVersions(a.slice(1), b.slice(1)));
    const earlier = ordered.filter((tag) => compareVersions(tag.slice(1), version) < 0);
    return earlier.at(-1) ?? null;
}

function compareVersions(a: string, b: string): number {
    const left = a.split(".").map(Number);
    const right = b.split(".").map(Number);
    for (let i = 0; i < 3; i += 1) {
        const delta = (left[i] ?? 0) - (right[i] ?? 0);
        if (delta !== 0) {
            return delta;
        }
    }
    return 0;
}

/** Splits "Some change (#144)" into its subject and PR number. */
export function parseSubject(raw: string): { subject: string; pull: number | null } {
    const match = /^(.*?)\s*\(#(\d+)\)$/.exec(raw);
    const subject = match?.[1];
    const pull = match?.[2];
    if (subject === undefined || pull === undefined) {
        return { subject: raw, pull: null };
    }
    return { subject, pull: Number(pull) };
}

function collectChanges(from: string | null, to: string): Change[] {
    const range = from === null ? to : `${from}..${to}`;
    // --first-parent so a squash-merged PR is one entry, not its branch
    // history. %b carries the body, which is where a real merge commit keeps
    // the branch's actual title.
    const lines = git(["log", "--first-parent", "--format=%H%x1f%s%x1f%b%x1e", range])
        .split("\x1e")
        .map((entry) => entry.trim())
        .filter((entry) => entry.length > 0);

    return lines
        .map((entry) => {
            const [sha = "", raw = "", body = ""] = entry.split("\x1f");
            const files = git(["show", "--name-only", "--format=", sha])
                .split("\n")
                .filter((path) => path.length > 0);
            const { subject, pull } = describeCommit(raw, body);
            return {
                subject,
                pull,
                watchFacing: files.some((path) => WATCH_PATHS.some((prefix) => path.startsWith(prefix))),
                releaseNote: releaseNoteOf(body),
            };
        })
        .filter((change) => !isReleaseMechanics(change.subject));
}

/**
 * A commit's `Release-note:` trailer, if it has one - what the change did, in
 * the words a user would use.
 *
 *     Release-note: Fixed the paused screen on Instinct watches.
 *
 * Commit subjects are written for whoever maintains this repo, and they should
 * stay that way: "Stop the paused headline hiding behind the Instinct's
 * subwindow" is an excellent commit subject and a useless line in a store
 * listing. This is how the two stop being the same sentence. Optional - a
 * change with no trailer falls back to its subject, and the generator lists
 * which ones did.
 */
export function releaseNoteOf(body: string): string | null {
    for (const line of body.split("\n")) {
        const match = /^\s*Release-note:\s*(.*)$/i.exec(line);
        // Trim after capturing rather than inside the pattern: a lazy group
        // against a trailing \s* happily matches a single space, so
        // "Release-note:   " would come back as " " instead of nothing.
        const note = match?.[1]?.trim();
        if (note !== undefined && note.length > 0) {
            return note;
        }
    }
    return null;
}

/**
 * A non-squash merge's subject is "Merge pull request #128 from owner/branch",
 * which says nothing about what changed - git puts the branch's real title in
 * the body instead. Prefer that when it is there.
 */
export function describeCommit(raw: string, body: string): { subject: string; pull: number | null } {
    const merge = /^Merge pull request #(\d+) from /.exec(raw);
    if (merge?.[1] !== undefined) {
        const title = body
            .split("\n")
            .map((line) => line.trim())
            .find((line) => line.length > 0);
        return { subject: title ?? raw, pull: Number(merge[1]) };
    }
    return parseSubject(raw);
}

/**
 * Version bumps touch AppVersion.mc, so they look watch-facing, but "Prepare
 * version 0.15.1" is the release itself rather than something in it.
 */
export function isReleaseMechanics(subject: string): boolean {
    return /^(Prepare|Bump) version /i.test(subject) || /^Release paperwork for v/i.test(subject);
}

/**
 * The headline after the version number. Fully automatic, so it needs a rule
 * rather than judgement: the first change that touches the watch, since that
 * is what a reader of a product update cares about. A release with no
 * watch-facing change says so plainly instead of dressing up tooling work.
 */
export function headline(changes: Change[]): string {
    const watchFacing = changes.find((change) => change.watchFacing);
    const first = watchFacing?.releaseNote ?? watchFacing?.subject;
    if (first === undefined) {
        return "tooling and test coverage";
    }
    return first.charAt(0).toLowerCase() + first.slice(1);
}

/**
 * `userWords` picks the Release-note trailer over the commit subject. On for
 * the watch-facing section, which people read to find out what changed for
 * them; off for tooling, which only makes sense in the repo's own vocabulary.
 * The PR link carries whoever wants the detail either way.
 */
function bullet(change: Change, userWords = false): string {
    const text = userWords ? (change.releaseNote ?? change.subject) : change.subject;
    if (change.pull === null) {
        return `- ${text}`;
    }
    return `- ${text} ([#${String(change.pull)}](${REPO_URL}/pull/${String(change.pull)}))`;
}

export function renderReleaseNotes(
    version: string,
    date: string,
    from: string | null,
    changes: Change[],
): string {
    const onWatch = changes.filter((change) => change.watchFacing);
    const behind = changes.filter((change) => !change.watchFacing);
    const since = from ?? "the first commit";

    const parts = [
        `# Mace & Clubs v${version}: ${headline(changes)}`,
        "",
        `${String(changes.length)} change${changes.length === 1 ? "" : "s"} since ${since} (${date}).`,
        "",
        "## On the watch",
        "",
    ];

    if (onWatch.length === 0) {
        parts.push("Nothing in this release changes the watch UI or behaviour.", "");
    } else {
        parts.push(...onWatch.map((change) => bullet(change, true)), "");
    }

    if (behind.length > 0) {
        parts.push("## Tooling and tests", "", ...behind.map((change) => bullet(change)), "");
    }

    parts.push(
        "## Install",
        "",
        `Download \`mace-clubs.iq\` from the [v${version} release](${REPO_URL}/releases/tag/v${version}),`,
        "or the Instinct 3 Solar sideload binary alongside it.",
        "",
        "---",
        "",
        "<!-- Generated by tools/release-docs.ts. Re-run `make release-docs` rather than editing. -->",
    );
    return parts.join("\n");
}

/**
 * Replaces the text between `<!-- generated:NAME -->` and
 * `<!-- /generated:NAME -->`, leaving everything else alone. The store
 * listing's prose is hand-written marketing copy worth keeping; only the
 * version-stamped parts are machine-owned.
 */
export function replaceRegion(document: string, name: string, replacement: string): string {
    const open = `<!-- generated:${name} -->`;
    const close = `<!-- /generated:${name} -->`;
    const start = document.indexOf(open);
    const end = document.indexOf(close);
    if (start === -1 || end === -1 || end < start) {
        throw new Error(`docs/store-listing.md is missing the ${open} ... ${close} markers`);
    }
    return document.slice(0, start + open.length) + "\n" + replacement + "\n" + document.slice(end);
}

export function renderWhatsNew(version: string, changes: Change[]): string {
    const onWatch = changes.filter((change) => change.watchFacing);
    const lines = [`## What's new — v${version}`, ""];
    if (onWatch.length === 0) {
        lines.push("Maintenance release: no changes to the watch UI or behaviour.");
    } else {
        // Store copy is plain text - no markdown links, per the note at the
        // top of store-listing.md. The user-facing wording wins here; the
        // commit subject is only the fallback.
        lines.push(...onWatch.map((change) => `- ${change.releaseNote ?? change.subject}`));
    }
    return lines.join("\n");
}

/**
 * The date a release carries. For a version that is already tagged, this is
 * the tag's own commit date rather than today: regenerating v0.7.0 next March
 * must not restamp it with next March. That made regeneration destructive, so
 * the archive could never be safely brought forward when the generator
 * changed - which is how nine product updates came to disagree with it.
 */
export function releaseDate(version: string, tagged: boolean, today: string): string {
    return tagged ? git(["log", "-1", "--format=%cs", `v${version}`]) : today;
}

/**
 * The trailer renderReleaseNotes stamps on its own output. Six of the nine
 * product updates predate the generator and are hand-written narratives -
 * v0.15.0's account of gyro-primary counting is real product writing, not a
 * bullet list. Nothing distinguished them, so `make release-docs VERSION=0.9.0`
 * would have silently replaced one with a changelog. This marker is what makes
 * a file the generator's to overwrite.
 */
const GENERATED_MARKER = "Generated by tools/release-docs.ts";

/** Whether the generator owns this file, or a person wrote it. */
export function isGenerated(existing: string | null): boolean {
    return existing === null || existing.includes(GENERATED_MARKER);
}

interface Paperwork {
    notesPath: string;
    notes: string;
    listingPath: string;
    /** Null when there is no store listing to refresh. */
    listing: string | null;
    changes: Change[];
    from: string | null;
}

/** Everything a release's paperwork should say, rendered but not yet written. */
function renderPaperwork(version: string): Paperwork {
    const tags = git(["tag", "--list"]).split("\n").filter((tag) => tag.length > 0);
    const from = previousTag(version, tags);
    // Normally this runs before tagging, so HEAD is the release. If the tag
    // already exists - regenerating an old release - use it, or the notes
    // would sweep in everything merged since.
    const tagged = tags.includes(`v${version}`);
    const to = tagged ? `v${version}` : "HEAD";
    const changes = collectChanges(from, to);
    const date = releaseDate(version, tagged, new Date().toISOString().slice(0, 10));

    const listingPath = join(REPO_ROOT, "docs", "store-listing.md");
    let listing: string | null = null;
    if (existsSync(listingPath)) {
        listing = readFileSync(listingPath, "utf8");
        listing = replaceRegion(
            listing,
            "upload",
            `Upload file: \`mace-clubs.iq\` from the v${version} GitHub release.`,
        );
        listing = replaceRegion(listing, "whatsnew", renderWhatsNew(version, changes));
    }

    return {
        notesPath: join(REPO_ROOT, "docs", "product-updates", `v${version}.md`),
        notes: renderReleaseNotes(version, date, from, changes) + "\n",
        listingPath,
        listing,
        changes,
        from,
    };
}

/**
 * Watch-facing changes whose wording will reach the store as a commit subject,
 * because they carry no Release-note trailer.
 */
function warnAboutUnworded(changes: Change[]): void {
    const unworded = changes.filter((change) => change.watchFacing && change.releaseNote === null);
    if (unworded.length === 0) {
        return;
    }
    console.warn(
        `\n${String(unworded.length)} watch-facing change${unworded.length === 1 ? "" : "s"} ` +
            "had no Release-note: trailer, so the store listing will quote the commit subject:",
    );
    for (const change of unworded) {
        console.warn(`  - ${change.subject}`);
    }
    console.warn("Edit docs/store-listing.md's What's new by hand, or see docs/releasing.md.\n");
}

/**
 * Reports which committed files disagree with what the generator now produces.
 * "Present" is not the same as "current": the paperwork check passed for
 * v0.16.0 while its title still said "Mace and Clubs", because nothing ever
 * compared the file against the generator that owns it.
 */
export function staleFiles(version: string): string[] {
    const work = renderPaperwork(version);
    const stale: string[] = [];
    const committed = (path: string): string | null =>
        existsSync(path) ? readFileSync(path, "utf8") : null;

    const existingNotes = committed(work.notesPath);
    // A hand-written narrative is not the generator's to have an opinion about.
    if (isGenerated(existingNotes) && existingNotes !== work.notes) {
        stale.push(`docs/product-updates/v${version}.md`);
    }
    if (work.listing !== null && committed(work.listingPath) !== work.listing) {
        stale.push("docs/store-listing.md");
    }
    return stale;
}

function main(): void {
    const args = process.argv.slice(2);
    const check = args.includes("--check");
    const version = args.find((arg) => !arg.startsWith("--"));
    if (version === undefined || !/^\d+\.\d+\.\d+$/.test(version)) {
        console.error("usage: release-docs.ts [--check] <version>   (e.g. 0.15.2)");
        process.exit(1);
    }

    if (check) {
        const stale = staleFiles(version);
        if (stale.length > 0) {
            console.error(
                `Release paperwork for v${version} is out of date with tools/release-docs.ts:`,
            );
            for (const path of stale) {
                console.error(`  - ${path}`);
            }
            console.error(`\nRegenerate and commit it:\n\n    make release-docs VERSION=${version}\n`);
            process.exit(1);
        }
        console.log(`Release paperwork for v${version} matches the generator.`);
        return;
    }

    const work = renderPaperwork(version);
    const existingNotes = existsSync(work.notesPath)
        ? readFileSync(work.notesPath, "utf8")
        : null;

    if (isGenerated(existingNotes)) {
        mkdirSync(dirname(work.notesPath), { recursive: true });
        writeFileSync(work.notesPath, work.notes);
        console.log(
            `wrote ${work.notesPath} (${String(work.changes.length)} changes since ${work.from ?? "the beginning"})`,
        );
    } else {
        console.warn(
            `kept ${work.notesPath} - it is hand-written, not generated output.\n` +
                "  Delete it first if you really want a generated changelog in its place.",
        );
    }

    warnAboutUnworded(work.changes);

    if (work.listing !== null) {
        writeFileSync(work.listingPath, work.listing);
        console.log(`refreshed ${work.listingPath}`);
    }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    main();
}
