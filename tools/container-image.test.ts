// Every job that runs Garmin's toolchain runs it on the same image.
//
// ghcr.io/matco/connectiq-tester supplies monkeyc, monkeydo, the simulator,
// the device files and - since v2.10.0 - the device fonts. Ten places name
// it: five jobs in ci.yml, both e2e workflows, the nightly headroom run, the
// release build, and the Dockerfile the Linux e2e image is built from.
//
// Three of those carried a comment saying to "bump the three occurrences
// together", written when there were three. Nobody recounted, and the one
// that drifted was release.yml, which stayed on :latest - so the job
// building the .iq that users install was the only one on a floating tag,
// which is precisely the arrangement the other comments argue against. That
// is the shape of a maintained number: correct when written, quietly wrong
// later, and nothing fails when it is.
//
// So the tag is checked rather than remembered. This does not say which
// version to use - it says that all of them agree and that none of them
// floats, which is what makes a green run mean something specific.

import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

/** Where the image can legitimately be named. */
const WORKFLOW_DIR = join(REPO_ROOT, ".github", "workflows");
const DOCKERFILE = join("tools", "e2e", "linux", "Dockerfile");

const IMAGE = "ghcr.io/matco/connectiq-tester";
/** Only tagged references; prose mentions the image without one. */
const TAGGED = /ghcr\.io\/matco\/connectiq-tester:([A-Za-z0-9._-]+)/g;

interface Reference {
    readonly file: string;
    readonly tag: string;
}

export function taggedReferences(file: string, contents: string): Reference[] {
    return [...contents.matchAll(TAGGED)].map((match) => ({ file, tag: match[1] ?? "" }));
}

function everyReference(): Reference[] {
    const files = [
        ...readdirSync(WORKFLOW_DIR)
            .filter((name) => name.endsWith(".yml"))
            .sort()
            .map((name) => join(".github", "workflows", name)),
        DOCKERFILE,
    ];
    return files.flatMap((file) => taggedReferences(file, readFileSync(join(REPO_ROOT, file), "utf8")));
}

void describe("taggedReferences", () => {
    it("reads the tag and ignores an untagged mention", () => {
        const found = taggedReferences("x.yml", `image: ${IMAGE}:v9.9.9\n# see ${IMAGE} for details\n`);
        assert.deepEqual(found, [{ file: "x.yml", tag: "v9.9.9" }]);
    });
});

void describe("the Connect IQ container image", () => {
    const references = everyReference();

    it("is named somewhere, so a rename cannot make this vacuous", () => {
        // Without this the two assertions below pass on an empty list, and a
        // moved workflow directory would read as every job agreeing.
        assert.ok(references.length >= 8, `expected the image in several places, found ${String(references.length)}`);
    });

    it("is pinned everywhere, never :latest", () => {
        const floating = references.filter((reference) => reference.tag === "latest");
        assert.deepEqual(
            floating.map((reference) => reference.file),
            [],
            "a floating tag is how v2.10.0's font rework reached these jobs unannounced",
        );
    });

    it("is the same version in every place that names it", () => {
        const tags = [...new Set(references.map((reference) => reference.tag))];
        assert.equal(
            tags.length,
            1,
            `the image is pinned to more than one version: ${references
                .map((reference) => `${reference.file} -> ${reference.tag}`)
                .join(", ")}`,
        );
    });
});
