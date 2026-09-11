// Every filesystem path in the e2e driver, resolved against the repo root.
//
// This directory is the one place in the repo where a relative path does not
// mean what it looks like. run-e2e.ts spawns each test file with
// `cwd: tools/e2e`, so that the file paths it passes to `node --test` resolve
// - which means "bin/mace-clubs.prg" written anywhere under here resolves to
// tools/e2e/bin/mace-clubs.prg, a directory that does not exist, rather than
// to the one at the repo root that every Makefile target and every document
// means by it.
//
// It has cost three separate bugs, and only one of them looked like a path:
//
//   - prgPath, fixed long ago and documented in simulator.ts's header, which
//     is where the pattern below comes from.
//   - MACE_E2E_COVERAGE_LOG, which resolved into a missing directory, so
//     appendFileSync threw ENOENT inside a stdout handler on every chunk and
//     the launch waiting for the app to draw reported "the simulator has no
//     window". A path bug that read as a broken simulator.
//   - two throwaway capture scripts, which wrote a screenshot nowhere and
//     died on the write.
//
// So: resolve here, once, and let the lint rule in eslint.config.mjs stop the
// next one being written. An absolute path is passed through untouched, so
// callers never have to ask which kind they were handed.
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

/** tools/e2e/ -> tools/ -> the repo root. */
export const REPO_ROOT = fileURLToPath(new URL("../..", import.meta.url));

/**
 * `relative` against the repo root, or itself when already absolute.
 *
 * Use this for every path that reaches the filesystem from this directory -
 * reads, writes, and anything handed to a child process - including paths
 * that arrived from an environment variable, which is where the worst of the
 * three bugs came from.
 */
export function repoPath(relative: string): string {
    return isAbsolute(relative) ? relative : join(REPO_ROOT, relative);
}
