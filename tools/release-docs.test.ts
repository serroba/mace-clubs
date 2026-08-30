// Unit tests for the release-paperwork generator. Everything asserted here is
// a pure function over a list of changes - the git plumbing that produces that
// list is exercised for real by `make release-docs`.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
    type Change,
    describeCommit,
    headline,
    isReleaseMechanics,
    parseSubject,
    previousTag,
    renderReleaseNotes,
    replaceRegion,
} from "./release-docs.ts";

const watch = (subject: string, pull: number | null = null): Change => ({ subject, pull, watchFacing: true });
const tooling = (subject: string, pull: number | null = null): Change => ({ subject, pull, watchFacing: false });

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
