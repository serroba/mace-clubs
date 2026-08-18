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
        files: ["eslint.config.mjs"],
        extends: [tseslint.configs.disableTypeChecked],
        rules: {
            "@typescript-eslint/explicit-function-return-type": "off",
            "@typescript-eslint/explicit-module-boundary-types": "off",
        },
    },
);
