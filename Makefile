DEVICE ?= instinct3solar45mm
DEVELOPER_KEY ?= developer_key.der
BIN_DIR ?= bin
NODE_TS := node --experimental-strip-types --disable-warning=ExperimentalWarning
TOOL_RESOLVER := $(NODE_TS) tools/resolve-tool.ts
JAVA ?= $(shell $(TOOL_RESOLVER) java)
MONKEYC ?= $(shell $(TOOL_RESOLVER) monkeyc)
MONKEYDO ?= $(shell $(TOOL_RESOLVER) monkeydo)
# rafiki is the whole monkey-c-rs toolchain in one binary - fmt, lint and
# coverage - since bombsimon/monkey-c-rs#8. The separate monkey-c-formatter
# and monkey-c-linter binaries no longer exist upstream; those crates are
# libraries now, and `cargo install` of them fails.
RAFIKI ?= $(shell $(TOOL_RESOLVER) rafiki)
JAVA_PATH := $(if $(findstring /,$(JAVA)),$(dir $(JAVA)):,)
export PATH := $(JAVA_PATH)$(PATH)

.PHONY: check pre-commit install-hooks doctor tools-check tool-resolver-test manifest-check xml fit-schema format format-check lint build test-build simulator-test tuning-search coverage clean brand-assets release-docs release-shots release-assets release-check

check: doctor tools-check xml fit-schema format-check lint build test-build

pre-commit:
	bash tools/pre_commit.sh

install-hooks:
	bash tools/install_hooks.sh

doctor:
	@command -v node >/dev/null || { echo "node is not on PATH (the local tooling needs Node.js 22+)"; exit 1; }
	@"$(JAVA)" -version >/dev/null 2>&1 || { echo "a working Java runtime was not found (or set JAVA=/path/to/java)"; exit 1; }
	@command -v "$(MONKEYC)" >/dev/null || { echo "monkeyc is not on PATH (or set MONKEYC=/path/to/monkeyc)"; exit 1; }
	@command -v "$(RAFIKI)" >/dev/null || { echo "rafiki was not found (cargo install --git https://github.com/bombsimon/monkey-c-rs rafiki, or set RAFIKI=/path/to/rafiki)"; exit 1; }
	@command -v xmllint >/dev/null || { echo "xmllint is not on PATH"; exit 1; }

# Typecheck, lint, and test every TypeScript tool. tools-check is the full
# gate; tool-resolver-test stays as the fast target CI's XML job uses.
tools-check:
	@test -d tools/node_modules || { echo "tools/node_modules missing - run: npm ci --prefix tools"; exit 1; }
	cd tools && npx tsc -p tsconfig.json && npx eslint . && $(NODE_TS) --test *.test.ts

tool-resolver-test:
	$(NODE_TS) --test tools/resolve-tool.test.ts

# Warning-only: reports CIQ 3.1+ wearables missing from manifest.xml.
manifest-check:
	bash tools/check_manifest_devices.sh

xml:
	@find . -name '*.xml' -not -path './.git/*' -print0 | xargs -0 -n1 xmllint --noout

fit-schema:
	bash tools/validate_fit_xml.sh

format:
	"$(RAFIKI)" fmt source

format-check:
	"$(RAFIKI)" fmt --check source

lint:
	"$(RAFIKI)" lint source

$(DEVELOPER_KEY):
	openssl genrsa -out $(DEVELOPER_KEY).pem 4096
	openssl pkcs8 -topk8 -inform PEM -outform DER -in $(DEVELOPER_KEY).pem -out $(DEVELOPER_KEY) -nocrypt
	$(RM) $(DEVELOPER_KEY).pem

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

build: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(MONKEYC)" -f monkey.jungle -d $(DEVICE) -o $(BIN_DIR)/mace-clubs.prg -y $(DEVELOPER_KEY)

# monkey.local.jungle keeps the offscreen render tests in local builds;
# CI's Linux simulator cannot draw device fonts offscreen (see
# RenderTestSupport) and compiles monkey.jungle instead.
test-build: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(MONKEYC)" -f monkey.local.jungle -d $(DEVICE) -o $(BIN_DIR)/mace-clubs-test.prg -y $(DEVELOPER_KEY) --unit-test

simulator-test: test-build
	"$(MONKEYDO)" $(BIN_DIR)/mace-clubs-test.prg $(DEVICE) -t

# SwingTuningSearch.mc's gyro-parameter grid search against the recorded
# replay fixtures - excluded from every other build via the swingTuning
# annotation, only monkey.tuning.jungle compiles it in. Slow (a few hundred
# combos replayed against two recordings); not part of `check`/`simulator-test`.
tuning-search: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(MONKEYC)" -f monkey.tuning.jungle -d $(DEVICE) -o $(BIN_DIR)/mace-clubs-tuning.prg -y $(DEVELOPER_KEY) --unit-test
	"$(MONKEYDO)" $(BIN_DIR)/mace-clubs-tuning.prg $(DEVICE) -t

# Function coverage of the unit tests, via rafiki
# (https://github.com/bombsimon/monkey-c-rs). The test subcommand runs the
# whole pipeline: instrument into bin/coverage, compile, run in the
# simulator (starting it if needed), and print the report. `source` is
# passed explicitly so stale instrumented copies under build/ or tmp/ are
# never swept into the build.
coverage: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(RAFIKI)" coverage test -d $(DEVICE) -y $(DEVELOPER_KEY) --start-simulator source

# Brand assets rendered from tools/brand-mark.ts: the SVG master, the store
# icon, and the site's favicons. Does not touch the app's launcher icon -
# brand-mark.test.ts pins the geometry to that bitmap instead. Commit what it
# produces; it is deterministic, so a re-run on an unchanged mark is a no-op.
brand-assets:
	$(NODE_TS) tools/render-brand-assets.ts

# Release paperwork. Both take VERSION=x.y.z and write into docs/; commit
# what they produce, then tag. The pre-push hook refuses a v* tag whose docs
# are missing or stale, which is what stops these going out of date again -
# 19 of the first 26 tags shipped with no product-update doc at all.
release-docs:
	@test -n "$(VERSION)" || { echo "usage: make release-docs VERSION=x.y.z"; exit 1; }
	$(NODE_TS) tools/release-docs.ts $(VERSION)

# Drives the real simulator, so it needs an awake, unlocked screen on macOS -
# same requirement as the e2e suite. Builds each device before shooting it.
release-shots:
	@test -n "$(VERSION)" || { echo "usage: make release-shots VERSION=x.y.z"; exit 1; }
	$(NODE_TS) tools/release-shots.ts $(VERSION)

release-assets: release-docs release-shots

# What the pre-push hook runs. Separate target so it can be checked by hand
# before tagging, rather than discovering a gap at push time.
release-check:
	@test -n "$(VERSION)" || { echo "usage: make release-check VERSION=x.y.z"; exit 1; }
	bash tools/check_release_docs.sh $(VERSION)

clean:
	$(RM) $(BIN_DIR)/mace-clubs.prg $(BIN_DIR)/mace-clubs-test.prg
