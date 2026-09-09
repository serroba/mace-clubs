// Unit tests for the release-paperwork generator. Almost everything asserted
// here is a pure function over a list of changes - the git plumbing that
// produces that list is exercised for real by `make release-docs`. The one
// exception is tagCommitDate, which runs git against a repository this file
// builds and throws away.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import {
    describeCommit,
    headline,
    isGenerated,
    isNotUserFacing,
    isReleaseMechanics,
    parseSubject,
    previousTag,
    releaseDate,
    releaseNoteOf,
    renderReleaseNotes,
    renderWhatsNew,
    replaceRegion,
    tagCommitDate,
    type Change,
} from "./release-docs.ts";

const watch = (subject: string, pull: number | null = null, releaseNote: string | null = null): Change => ({
    subject,
    pull,
    watchFacing: true,
    releaseNote,
});
const tooling = (subject: string, pull: number | null = null): Change => ({
    subject,
    pull,
    watchFacing: false,
    releaseNote: null,
});

void describe("previousTag", () => {
    const tags = ["v0.14.0", "v0.14.1", "v0.15.0", "v0.15.1", "v0.9.1", "v0.10.0"];

    it("orders by version, not lexically", () => {
        // The bug this guards: "v0.9.1" sorts after "v0.10.0" as a string.
        assert.equal(previousTag("0.14.0", tags), "v0.10.0");
    });

    it("finds the tag immediately before the version being released", () => {
        assert.equal(previousTag("0.15.2", tags), "v0.15.1");
        assert.equal(previousTag("0.15.0", tags), "v0.14.1");
    });

    it("returns null for the very first release", () => {
        assert.equal(previousTag("0.1.0", tags), null);
    });

    it("ignores tags that are not versions", () => {
        assert.equal(previousTag("0.15.2", [...tags, "nightly", "v1.2"]), "v0.15.1");
    });
});

void describe("parseSubject", () => {
    it("splits a squash-merge subject from its PR number", () => {
        assert.deepEqual(parseSubject("Fix the thing (#144)"), { subject: "Fix the thing", pull: 144 });
    });

    it("leaves a direct commit alone", () => {
        assert.deepEqual(parseSubject("Fix the thing"), { subject: "Fix the thing", pull: null });
    });

    it("does not mistake a trailing parenthetical for a PR reference", () => {
        assert.deepEqual(parseSubject("Bump the cap (now 16)"), { subject: "Bump the cap (now 16)", pull: null });
    });
});

void describe("describeCommit", () => {
    it("takes a merge commit's title from the body, not its useless subject", () => {
        assert.deepEqual(
            describeCommit("Merge pull request #128 from serroba/codex/add-fixtures", "Add workout FIT fixtures\n"),
            { subject: "Add workout FIT fixtures", pull: 128 },
        );
    });

    it("falls back to the subject when a merge commit has no body", () => {
        const raw = "Merge pull request #128 from serroba/codex/add-fixtures";
        assert.deepEqual(describeCommit(raw, ""), { subject: raw, pull: 128 });
    });

    it("leaves a squash-merge subject alone", () => {
        assert.deepEqual(describeCommit("Fix the thing (#144)", "body text"), {
            subject: "Fix the thing",
            pull: 144,
        });
    });
});

void describe("isReleaseMechanics", () => {
    // These touch AppVersion.mc, so they look watch-facing, but they are the
    // release rather than anything in it.
    it("recognises a version bump", () => {
        assert.ok(isReleaseMechanics("Prepare version 0.15.1"));
        assert.ok(isReleaseMechanics("Bump version 0.16.0"));
        assert.ok(isReleaseMechanics("Release paperwork for v0.15.1"));
    });

    it("leaves real changes alone", () => {
        assert.ok(!isReleaseMechanics("Prepare the rest screen for paging"));
        assert.ok(!isReleaseMechanics("Fix the app crashing on workout start"));
    });
});

void describe("headline", () => {
    it("uses the first watch-facing change", () => {
        assert.equal(headline([tooling("Speed up CI"), watch("Add a rest screen")]), "add a rest screen");
    });

    it("says so plainly when nothing touches the watch", () => {
        assert.equal(headline([tooling("Speed up CI")]), "tooling and test coverage");
    });
});

void describe("renderReleaseNotes", () => {
    it("separates what changed on the watch from the tooling", () => {
        const notes = renderReleaseNotes("0.16.0", "2026-08-30", "v0.15.1", [
            watch("Add a rest screen", 200),
            tooling("Speed up CI", 201),
        ]);
        const onWatch = notes.indexOf("## On the watch");
        const behind = notes.indexOf("## Tooling and tests");
        assert.ok(onWatch < notes.indexOf("Add a rest screen"), "watch change sits under the watch heading");
        assert.ok(behind > notes.indexOf("Add a rest screen"), "tooling section comes after");
        assert.ok(notes.includes("/pull/200"), "links the PR");
    });

    it("states outright when a release changes nothing on the watch", () => {
        const notes = renderReleaseNotes("0.16.0", "2026-08-30", "v0.15.1", [tooling("Speed up CI")]);
        assert.match(notes, /Nothing in this release changes the watch UI or behaviour\./);
        assert.ok(!notes.includes("## Tooling and tests\n\n\n"), "no empty section");
    });

    it("counts changes and names the range", () => {
        const notes = renderReleaseNotes("0.16.0", "2026-08-30", "v0.15.1", [watch("One"), watch("Two")]);
        assert.match(notes, /2 changes since v0\.15\.1 \(2026-08-30\)/);
    });

    it("says one change, not 1 changes", () => {
        const notes = renderReleaseNotes("0.16.0", "2026-08-30", "v0.15.1", [watch("One")]);
        assert.match(notes, /1 change since/);
    });

    it("handles a first release with no previous tag", () => {
        const notes = renderReleaseNotes("0.1.0", "2026-08-30", null, [watch("One")]);
        assert.match(notes, /since the first commit/);
    });
});

void describe("replaceRegion", () => {
    const doc = "keep me\n<!-- generated:x -->\nold\n<!-- /generated:x -->\nkeep me too\n";

    it("replaces only what is between the markers", () => {
        const out = replaceRegion(doc, "x", "new");
        assert.match(out, /keep me\n<!-- generated:x -->\nnew\n<!-- \/generated:x -->\nkeep me too/);
        assert.ok(!out.includes("old"));
    });

    it("is idempotent", () => {
        assert.equal(replaceRegion(replaceRegion(doc, "x", "new"), "x", "new"), replaceRegion(doc, "x", "new"));
    });

    it("refuses a document without the markers rather than guessing", () => {
        assert.throws(() => replaceRegion("no markers here", "x", "new"), /missing the/);
    });
});

void describe("Release-note trailers", () => {
    it("reads the trailer out of a commit body", () => {
        assert.equal(
            releaseNoteOf("Some detail.\n\nRelease-note: Fixed the paused screen on Instinct watches.\n"),
            "Fixed the paused screen on Instinct watches.",
        );
    });

    it("is absent when the commit has no trailer", () => {
        assert.equal(releaseNoteOf("Just a body.\n\nCo-Authored-By: Someone\n"), null);
        assert.equal(releaseNoteOf(""), null);
        assert.equal(releaseNoteOf("Release-note:   \n"), null);
    });

    it("prefers user wording in the store listing, and falls back to the subject", () => {
        const changes = [
            watch("Stop the paused headline hiding behind the Instinct's subwindow", 149, "Fixed the paused screen on Instinct watches."),
            watch("Make the app-drawn screens scale to the device", 145),
        ];
        const listing = replaceRegion(
            "<!-- generated:whatsnew -->\nold\n<!-- /generated:whatsnew -->",
            "whatsnew",
            renderWhatsNew("0.17.0", changes),
        );
        assert.match(listing, /Fixed the paused screen on Instinct watches\./);
        assert.doesNotMatch(listing, /subwindow/);
        // No trailer, so the commit subject stands in rather than nothing.
        assert.match(listing, /Make the app-drawn screens scale to the device/);
    });

    it("uses user wording for the headline and the on-watch bullets", () => {
        const notes = renderReleaseNotes("0.17.0", "2026-08-30", "v0.16.0", [
            watch("Stop the paused headline hiding behind the Instinct's subwindow", 149, "Fixed the paused screen on Instinct watches."),
            tooling("Run the e2e UI suite on Linux in CI", 141),
        ]);
        // One sentence, and no trailing stop: this is a title, and a release
        // note may be a paragraph.
        assert.match(notes, /# Mace & Clubs v0\.17\.0: fixed the paused screen on Instinct watches\n/);
        // The bullet reads in user words but keeps its PR link.
        assert.match(notes, /- Fixed the paused screen on Instinct watches\. \(\[#149\]/);
        // Tooling keeps the repo's own vocabulary.
        assert.match(notes, /- Run the e2e UI suite on Linux in CI \(\[#141\]/);
    });
});

void describe("hand-written product updates", () => {
    // Six of the nine product updates predate the generator and are real
    // narrative writing. Nothing marked them, so `make release-docs
    // VERSION=0.9.0` would have replaced one with a bullet list.
    it("recognises generated output by its trailer", () => {
        assert.equal(
            isGenerated("# v1\n\n<!-- Generated by tools/release-docs.ts. Re-run it. -->"),
            true,
        );
    });

    it("treats a file with no trailer as someone's writing", () => {
        assert.equal(isGenerated("# Mace & Clubs v0.15.0: gyroscope-primary mace counting\n\nProse."), false);
    });

    it("treats an absent file as the generator's to create", () => {
        assert.equal(isGenerated(null), true);
    });
});

void describe("releaseDate", () => {
    it("uses today for a version that is not tagged yet", () => {
        assert.equal(releaseDate("9.9.9", false, "2026-08-31"), "2026-08-31");
    });

    it("uses the tag's own date when regenerating a released version", () => {
        // Otherwise regenerating v0.7.0 next March restamps it with March,
        // which made bringing the archive forward destructive.
        assert.equal(
            releaseDate("0.7.0", true, "2026-08-31", (version) => `tag-date-of-${version}`),
            "tag-date-of-0.7.0",
        );
    });
});

// The other half: that the git invocation itself returns a tag's commit date
// in the format the paperwork wants. Against a repository this test builds,
// not against this one - asserting on v0.16.0 meant the test needed a tag
// nobody had promised to keep, and it failed the first time CI ran it because
// actions/checkout fetches no tags at all.
void describe("tagCommitDate", () => {
    it("reads the tag's commit date, not today's", () => {
        const repo = mkdtempSync(join(tmpdir(), "release-docs-tag-"));
        try {
            const run = (...args: string[]): void => {
                execFileSync("git", args, {
                    cwd: repo,
                    env: {
                        ...process.env,
                        GIT_AUTHOR_DATE: "2020-01-02T03:04:05Z",
                        GIT_COMMITTER_DATE: "2020-01-02T03:04:05Z",
                        GIT_AUTHOR_NAME: "Test",
                        GIT_AUTHOR_EMAIL: "test@example.com",
                        GIT_COMMITTER_NAME: "Test",
                        GIT_COMMITTER_EMAIL: "test@example.com",
                    },
                });
            };
            run("init", "--quiet");
            writeFileSync(join(repo, "file.txt"), "content\n");
            run("add", "file.txt");
            run("commit", "--quiet", "-m", "Only commit");
            run("tag", "v9.9.9");

            assert.equal(tagCommitDate("9.9.9", repo), "2020-01-02");
        } finally {
            rmSync(repo, { recursive: true, force: true });
        }
    });
});


void describe("non-user-facing changes", () => {
    it("a change whose note says it is not user-facing stays out of the store listing", () => {
      // The repo writes "Release-note: Nothing user-facing - CI reporting only"
      // on changes that touch source/ for reasons nobody outside the repo cares
      // about - #168 moved a test file and was classed watch-facing for it.
      // v0.17.0 was one command away from shipping that sentence to the Connect
      // IQ store as a feature.
      const changes = [
        { subject: "Move to rafiki", pull: 168, watchFacing: true, releaseNote: "Nothing user-facing - developer tooling only." },
        { subject: "Colour the work phase", pull: 166, watchFacing: true, releaseNote: "Work intervals now show in colour." },
      ];
      const whatsNew = renderWhatsNew("0.17.0", changes);
      assert.doesNotMatch(whatsNew, /Nothing user-facing/);
      assert.match(whatsNew, /Work intervals now show in colour/);
    });

    it("but it still appears in the changelog, under tooling", () => {
      // Dropping it from both would be worse than quoting it: the product update
      // is the record of what shipped, so everything belongs somewhere in it.
      const changes = [
        { subject: "Move to rafiki", pull: 168, watchFacing: true, releaseNote: "Nothing user-facing - developer tooling only." },
      ];
      const notes = renderReleaseNotes("0.17.0", "2026-09-08", "v0.16.0", changes);
      const toolingSection = notes.slice(notes.indexOf("## Tooling and tests"));
      assert.match(toolingSection, /Move to rafiki/);
      // The watch section is still written, saying there was nothing - which
      // is the truth once this change is classified correctly.
      assert.match(notes, /Nothing in this release changes the watch UI/);
    });

    it("isNotUserFacing reads the convention, not any sentence with those words", () => {
      assert.equal(isNotUserFacing("Nothing user-facing - CI only."), true);
      assert.equal(isNotUserFacing("nothing user facing"), true);
      assert.equal(isNotUserFacing(null), false);
      // A real note that happens to discuss the phrase is still a real note.
      assert.equal(isNotUserFacing("Fixed a screen that showed nothing user-facing at all."), false);
    });
});
