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
CONNECTIQ ?= $(shell $(TOOL_RESOLVER) connectiq)
JAVA_PATH := $(if $(findstring /,$(JAVA)),$(dir $(JAVA)):,)
export PATH := $(JAVA_PATH)$(PATH)

.PHONY: quality check pre-commit install-hooks doctor tools-check tool-resolver-test manifest-check xml fit-schema format format-check lint build test-build simulator-test tuning-search coverage coverage-e2e coverage-all e2e-image e2e-image-if-missing e2e-docker e2e-file clean brand-assets release-docs release-shots release-assets release-check

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

# What the e2e suite covers, which the unit figure above cannot see.
#
# `make coverage` reports 70%, and the 30% it does not reach is mostly the
# code a unit test cannot call: onUpdate and the draw helpers under it, the
# delegates' onSelect/onBack/onTap, the menu builders. That code is not
# untested - it is what the e2e suite exists to exercise, on thirteen devices.
# Reporting only the unit number described the app as less tested than it is,
# and the honest fix is to measure the other half rather than to argue about
# it.
#
# The mechanism is the same one rafiki already uses. Its probe is a println -
# "COVHIT <id>" the first time each function body runs - so any captured
# simulator log is a coverage log. `instrument` even writes a jungle mirroring
# monkey.jungle's exclusions, so the instrumented app builds as a normal app
# rather than as a test binary. MACE_E2E_PRG points the suite's own test files
# at it; MACE_E2E_COVERAGE_LOG keeps monkeydo's output instead of draining it.
#
# The suite drives one device (DEVICE), not thirteen: the annotations differ
# per device but the function bodies do not, so a second device would re-cover
# the same ids more slowly. Takes as long as the e2e suite does.
coverage-e2e: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(RAFIKI)" coverage instrument source
	"$(MONKEYC)" -f $(BIN_DIR)/coverage/coverage.jungle -d $(DEVICE) \
		-o $(BIN_DIR)/mace-clubs-cov.prg -y $(DEVELOPER_KEY)
	$(RM) $(BIN_DIR)/coverage-e2e.log
	MACE_E2E_PRG=$(BIN_DIR)/mace-clubs-cov.prg \
		MACE_E2E_COVERAGE_LOG=$(BIN_DIR)/coverage-e2e.log \
		caffeinate -dimsu npm run test:e2e --prefix tools
	"$(RAFIKI)" coverage report $(BIN_DIR)/coverage-e2e.log

# Both suites against one manifest: the union of what the unit tests and the
# e2e suite reach, which is the closest thing to "what this project tests".
#
# One instrument step feeds both, because the function ids have to mean the
# same thing in both logs - re-instrumenting between them would renumber
# everything and the union would be nonsense.
coverage-all: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(RAFIKI)" coverage instrument source
	"$(MONKEYC)" -f $(BIN_DIR)/coverage/coverage.jungle -d $(DEVICE) \
		-o $(BIN_DIR)/mace-clubs-cov-test.prg -y $(DEVELOPER_KEY) --unit-test
	@# monkeydo does not start a simulator and says "Unable to connect" when
	@# there is none, which `|| true` then swallows into an empty log and a
	@# report of 0%. The e2e half below starts its own; this half has to be
	@# given one. `make coverage` avoids the problem with rafiki's
	@# --start-simulator, which does not hand back the log this needs.
	@pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" >/dev/null 2>&1 \
		|| pgrep -f "bin/simulator" >/dev/null 2>&1 \
		|| { echo "starting the simulator"; "$(CONNECTIQ)" >/dev/null 2>&1 & sleep 12; }
	"$(MONKEYDO)" $(BIN_DIR)/mace-clubs-cov-test.prg $(DEVICE) -t \
		> $(BIN_DIR)/coverage-unit.log 2>&1 || true
	@grep -q COVHIT $(BIN_DIR)/coverage-unit.log \
		|| { echo "::error::the unit half captured nothing - $$(head -1 $(BIN_DIR)/coverage-unit.log)"; exit 1; }
	"$(MONKEYC)" -f $(BIN_DIR)/coverage/coverage.jungle -d $(DEVICE) \
		-o $(BIN_DIR)/mace-clubs-cov.prg -y $(DEVELOPER_KEY)
	$(RM) $(BIN_DIR)/coverage-e2e.log
	MACE_E2E_PRG=$(BIN_DIR)/mace-clubs-cov.prg \
		MACE_E2E_COVERAGE_LOG=$(BIN_DIR)/coverage-e2e.log \
		caffeinate -dimsu npm run test:e2e --prefix tools
	@echo
	@echo "== unit tests alone"
	@"$(RAFIKI)" coverage report $(BIN_DIR)/coverage-unit.log | tail -1
	@echo "== e2e suite alone"
	@"$(RAFIKI)" coverage report $(BIN_DIR)/coverage-e2e.log | tail -1
	@echo "== both"
	@cat $(BIN_DIR)/coverage-unit.log $(BIN_DIR)/coverage-e2e.log \
		| "$(RAFIKI)" coverage report - | tail -1

# The e2e suite in the Linux container, which is the answer whenever the
# macOS driver cannot run: that one needs an awake, unlocked display, and
# caffeinate keeps a display awake but cannot unlock one. A container does not
# care what the screen is doing.
#
# These exist because their absence kept producing throwaway scripts. Writing
# the weight-editor test meant six runs of one file, and each hand-rolled
# runner was a fresh chance to write a path relative to the wrong directory -
# which is two of the three bugs behind tools/e2e/repo-path.ts.
#
#   make e2e-docker                              # the whole suite
#   make e2e-file FILE=full/history.e2e.test.ts  # one file, for iterating
#   make e2e-file FILE=... DEVICE=venu3          # ... on another watch
#
# DEVICE is the same variable every other target uses, defaulting to the
# gyro-validated Instinct 3 Solar.
E2E_IMAGE ?= mace-clubs-e2e-linux:local

e2e-image:
	docker build -t $(E2E_IMAGE) -f tools/e2e/linux/Dockerfile .

# Built if absent, so a first run needs no separate step; `make e2e-image`
# rebuilds it after a Dockerfile change.
e2e-docker: | e2e-image-if-missing
	docker run --rm --entrypoint bash \
		-e MACE_E2E_DEVICE=$(DEVICE) \
		-v "$(CURDIR):/workspace" -w /workspace $(E2E_IMAGE) \
		/workspace/tools/e2e/linux/run-suite.sh

e2e-file: | e2e-image-if-missing
	@test -n "$(FILE)" || { echo "usage: make e2e-file FILE=full/history.e2e.test.ts [DEVICE=venu3]"; exit 1; }
	docker run --rm --entrypoint bash \
		-e MACE_E2E_DEVICE=$(DEVICE) \
		-v "$(CURDIR):/workspace" -w /workspace $(E2E_IMAGE) \
		/workspace/tools/e2e/linux/run-file.sh "$(FILE)"

e2e-image-if-missing:
	@docker image inspect $(E2E_IMAGE) >/dev/null 2>&1 || $(MAKE) e2e-image

# The project's quality signals as a markdown table - device counts, matrix
# sizes, coverage, lint rules - every figure derived from the manifest and the
# workflow files rather than restated. CI appends the same table to its job
# summary. Coverage is only included when a run measured it.
# How much memory the app has left at its peak, per device.
# The check whose absence let the app ship unable to start on the Instinct 2
# for four months: the build sweep proves 120 devices compile, and compiling
# says nothing about whether a watch can hold what it compiled.
#
# Defaults to the tier where the answer can change - everything at or below
# 128KB. `make memory-headroom DEVICES="venu3 fenix7"` checks named devices,
# and the nightly workflow runs --all.
memory-headroom: $(DEVELOPER_KEY)
	@$(NODE_TS) tools/memory-headroom.ts $(if $(DEVICES),$(DEVICES),--at-risk)

# Re-record tools/memory-baselines.json after a change that legitimately costs
# headroom. Review the diff: a device losing 2KB is the size of drop that made
# the app stop starting, and it is worth knowing what bought it.
memory-headroom-record: $(DEVELOPER_KEY)
	@$(NODE_TS) tools/memory-headroom.ts $(if $(DEVICES),$(DEVICES),--at-risk) --record

quality:
	@$(NODE_TS) tools/quality-report.ts --lint-rules "$$('$(RAFIKI)' lint --list-rules | wc -l | tr -d ' ')"

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
