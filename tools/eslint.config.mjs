// Maximum-strictness lint for the local FIT tooling: every type-aware
// typescript-eslint preset plus the opt-in pedantic rules they leave out.
// Deliberate exclusions, with reasons:
//   - no-magic-numbers: chart geometry and the FIT wire format are numbers.
//   - naming-convention: FIT developer fields and report JSON are snake_case
//     by contract with the recorded files and the report template.
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
    { ignores: [".venv/", "__pycache__/", "node_modules/"] },
    eslint.configs.recommended,
    tseslint.configs.strictTypeChecked,
    tseslint.configs.stylisticTypeChecked,
    {
        languageOptions: {
            parserOptions: {
                projectService: true,
                tsconfigRootDir: import.meta.dirname,
            },
        },
        linterOptions: {
            reportUnusedDisableDirectives: "error",
        },
        rules: {
            "@typescript-eslint/consistent-type-imports": ["error", { fixStyle: "inline-type-imports" }],
            "@typescript-eslint/explicit-function-return-type": "error",
            "@typescript-eslint/explicit-module-boundary-types": "error",
            "@typescript-eslint/no-shadow": "error",
            "@typescript-eslint/no-unnecessary-qualifier": "error",
            "@typescript-eslint/no-useless-empty-export": "error",
            "@typescript-eslint/prefer-readonly": "error",
            "@typescript-eslint/promise-function-async": "error",
            "@typescript-eslint/require-array-sort-compare": "error",
            "@typescript-eslint/strict-boolean-expressions": [
                "error",
                {
                    allowString: false,
                    allowNumber: false,
                    allowNullableObject: false,
                    allowNullableBoolean: false,
                    allowNullableString: false,
                    allowNullableNumber: false,
                    allowNullableEnum: false,
                    allowAny: false,
                },
            ],
            "@typescript-eslint/switch-exhaustiveness-check": [
                "error",
                { considerDefaultExhaustiveForUnions: true, requireDefaultForNonUnion: true },
            ],
            // Loose equality is banned except the `x != null` idiom, which is
            // the intended way to cover null|undefined in the report model.
            "eqeqeq": ["error", "always", { null: "ignore" }],
            "@typescript-eslint/no-floating-promises": [
                "error",
                { allowForKnownSafeCalls: [{ from: "package", name: "test", package: "node:test" }] },
            ],
            "no-console": "off",
        },
    },
    {
        // The e2e driver runs with cwd = tools/e2e, not the repo root:
        // run-e2e.ts spawns each test file from this directory so that the
        // paths it hands `node --test` resolve. Every other part of the repo -
        // the Makefile, the docs, the other tools - says "bin/mace-clubs.prg"
        // and means the repo root, so a relative path written here silently
        // means a different, missing directory.
        //
        // It has cost three bugs and only one of them looked like a path; see
        // e2e/repo-path.ts. Documenting it did not stop the second or the
        // third, so it is a lint error now: pass filesystem paths through
        // repoPath() and the question does not arise.
        files: ["e2e/**/*.ts"],
        rules: {
            "no-restricted-syntax": [
                "error",
                {
                    selector:
                        "CallExpression[callee.name=/^(appendFile|copyFile|createReadStream|createWriteStream|mkdir|open|readFile|readdir|rm|stat|unlink|writeFile)(Sync)?$/]" +
                        "[arguments.0.type='Literal'][arguments.0.value=/^[^/]/]",
                    message:
                        "Relative path in tools/e2e: this code runs with cwd=tools/e2e, so it will not " +
                        "resolve where you mean. Wrap it in repoPath() from ./repo-path.ts.",
                },
                {
                    selector:
                        "CallExpression[callee.property.name=/^(appendFile|copyFile|createReadStream|createWriteStream|mkdir|open|readFile|readdir|rm|stat|unlink|writeFile)(Sync)?$/]" +
                        "[arguments.0.type='Literal'][arguments.0.value=/^[^/]/]",
                    message:
                        "Relative path in tools/e2e: this code runs with cwd=tools/e2e, so it will not " +
                        "resolve where you mean. Wrap it in repoPath() from ./repo-path.ts.",
                },
            ],
        },
    },
    {
        files: ["eslint.config.mjs"],
        extends: [tseslint.configs.disableTypeChecked],
        rules: {
            "@typescript-eslint/explicit-function-return-type": "off",
            "@typescript-eslint/explicit-module-boundary-types": "off",
        },
    },
);
