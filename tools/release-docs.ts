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
            };
        })
        .filter((change) => !isReleaseMechanics(change.subject));
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
    const first = changes.find((change) => change.watchFacing)?.subject;
    if (first === undefined) {
        return "tooling and test coverage";
    }
    return first.charAt(0).toLowerCase() + first.slice(1);
}

function bullet(change: Change): string {
    if (change.pull === null) {
        return `- ${change.subject}`;
    }
    return `- ${change.subject} ([#${String(change.pull)}](${REPO_URL}/pull/${String(change.pull)}))`;
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
        `# Mace and Clubs v${version}: ${headline(changes)}`,
        "",
        `${String(changes.length)} change${changes.length === 1 ? "" : "s"} since ${since} (${date}).`,
        "",
        "## On the watch",
        "",
    ];

    if (onWatch.length === 0) {
        parts.push("Nothing in this release changes the watch UI or behaviour.", "");
    } else {
        parts.push(...onWatch.map(bullet), "");
    }

    if (behind.length > 0) {
        parts.push("## Tooling and tests", "", ...behind.map(bullet), "");
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

function renderWhatsNew(version: string, changes: Change[]): string {
    const onWatch = changes.filter((change) => change.watchFacing);
    const lines = [`## What's new — v${version}`, ""];
    if (onWatch.length === 0) {
        lines.push("Maintenance release: no changes to the watch UI or behaviour.");
    } else {
        // Store copy is plain text - no markdown links, per the note at the
        // top of store-listing.md.
        lines.push(...onWatch.map((change) => `- ${change.subject}`));
    }
    return lines.join("\n");
}

function main(): void {
    const version = process.argv[2];
    if (version === undefined || !/^\d+\.\d+\.\d+$/.test(version)) {
        console.error("usage: release-docs.ts <version>   (e.g. 0.15.2)");
        process.exit(1);
    }

    const tags = git(["tag", "--list"]).split("\n").filter((tag) => tag.length > 0);
    const from = previousTag(version, tags);
    // Normally this runs before tagging, so HEAD is the release. If the tag
    // already exists - regenerating an old release - use it, or the notes
    // would sweep in everything merged since.
    const to = tags.includes(`v${version}`) ? `v${version}` : "HEAD";
    const changes = collectChanges(from, to);
    const date = new Date().toISOString().slice(0, 10);

    const notesPath = join(REPO_ROOT, "docs", "product-updates", `v${version}.md`);
    mkdirSync(dirname(notesPath), { recursive: true });
    writeFileSync(notesPath, renderReleaseNotes(version, date, from, changes) + "\n");
    console.log(`wrote ${notesPath} (${String(changes.length)} changes since ${from ?? "the beginning"})`);

    const listingPath = join(REPO_ROOT, "docs", "store-listing.md");
    if (existsSync(listingPath)) {
        let listing = readFileSync(listingPath, "utf8");
        listing = replaceRegion(
            listing,
            "upload",
            `Upload file: \`mace-clubs.iq\` from the v${version} GitHub release.`,
        );
        listing = replaceRegion(listing, "whatsnew", renderWhatsNew(version, changes));
        writeFileSync(listingPath, listing);
        console.log(`refreshed ${listingPath}`);
    }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    main();
}
