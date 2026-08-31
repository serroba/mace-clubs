import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SITE = join(REPO_ROOT, "docs");

const html = (): string => readFileSync(join(SITE, "index.html"), "utf8");

/** Local src=/href= targets - anything absolute or off-site is someone else's. */
function localReferences(source: string): string[] {
  return [...source.matchAll(/(?:src|href)="([^"#]+)"/g)]
    .map((match) => match[1] ?? "")
    .filter((ref) => ref !== "" && !/^(https?:)?\/\//.test(ref) && !ref.startsWith("mailto:"));
}

// The site points at release-versioned capture paths
// (store-assets/v0.16.0/...), which `make release-shots` writes into a new
// folder each release. Nothing stops the old path being deleted or the site
// keeping a path that no longer exists, and a hero image that 404s is not
// something anyone notices from the terminal.
test("every local asset the site references exists", () => {
  const missing = localReferences(html()).filter((ref) => !existsSync(join(SITE, ref)));
  assert.deepEqual(missing, [], `docs/index.html references files that do not exist: ${missing.join(", ")}`);
});

test("the social card is declared with the dimensions it actually has", () => {
  const source = html();
  for (const property of [
    "og:title",
    "og:description",
    "og:image",
    "og:url",
    "twitter:card",
    "twitter:image",
  ]) {
    assert.match(
      source,
      new RegExp(`(?:property|name)="${property.replace(":", ":")}"`),
      `docs/index.html is missing the ${property} meta tag`,
    );
  }
  // Facebook and LinkedIn trust the declared size over the file, so a wrong
  // one crops the card rather than failing visibly.
  const width = /og:image:width" content="(\d+)"/.exec(source)?.[1];
  const height = /og:image:height" content="(\d+)"/.exec(source)?.[1];
  assert.equal(width, "1200");
  assert.equal(height, "630");

  const image = /og:image" content="[^"]*\/([^/"]+)"/.exec(source)?.[1];
  assert.ok(image !== undefined, "og:image should name a file");
  assert.ok(
    existsSync(join(SITE, "brand", image)),
    `og:image names brand/${image}, which does not exist`,
  );
});

test("images carry alt text, or are marked decorative", () => {
  // The captures are the argument the page is making; a screen reader that
  // gets "image" learns nothing about what the app looks like.
  //
  // An empty alt is the exception, and it is a deliberate one: the mark beside
  // the wordmark in the nav says nothing the wordmark does not already say, so
  // describing it makes a screen reader announce the name twice. What is not
  // acceptable is a missing alt attribute, or a one-word placeholder.
  for (const tag of html().match(/<img\b[^>]*>/g) ?? []) {
    const alt = /\balt="([^"]*)"/.exec(tag)?.[1];
    assert.ok(alt !== undefined, `<img> with no alt attribute at all: ${tag.slice(0, 80)}`);
    if (alt === "") continue;
    assert.ok(
      alt.length >= 10,
      `<img> with placeholder alt text: ${tag.slice(0, 80)}`,
    );
  }
});
