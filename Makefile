DEVICE ?= instinct3solar45mm
DEVELOPER_KEY ?= developer_key.der
BIN_DIR ?= bin
NODE_TS := node --experimental-strip-types --disable-warning=ExperimentalWarning
TOOL_RESOLVER := $(NODE_TS) tools/resolve-tool.ts
JAVA ?= $(shell $(TOOL_RESOLVER) java)
MONKEYC ?= $(shell $(TOOL_RESOLVER) monkeyc)
MONKEYDO ?= $(shell $(TOOL_RESOLVER) monkeydo)
FORMATTER ?= $(shell $(TOOL_RESOLVER) monkey-c-formatter)
LINTER ?= $(shell $(TOOL_RESOLVER) monkey-c-linter)
RAFIKI ?= $(shell $(TOOL_RESOLVER) rafiki)
JAVA_PATH := $(if $(findstring /,$(JAVA)),$(dir $(JAVA)):,)
export PATH := $(JAVA_PATH)$(PATH)

.PHONY: check pre-commit install-hooks doctor tools-check tool-resolver-test manifest-check xml fit-schema format format-check lint build test-build simulator-test coverage clean

check: doctor tools-check xml fit-schema format-check lint build test-build

pre-commit:
	bash tools/pre_commit.sh

install-hooks:
	bash tools/install_hooks.sh

doctor:
	@command -v node >/dev/null || { echo "node is not on PATH (the local tooling needs Node.js 22+)"; exit 1; }
	@"$(JAVA)" -version >/dev/null 2>&1 || { echo "a working Java runtime was not found (or set JAVA=/path/to/java)"; exit 1; }
	@command -v "$(MONKEYC)" >/dev/null || { echo "monkeyc is not on PATH (or set MONKEYC=/path/to/monkeyc)"; exit 1; }
	@command -v "$(FORMATTER)" >/dev/null || { echo "monkey-c-formatter was not found (install it with cargo or set FORMATTER=/path/to/monkey-c-formatter)"; exit 1; }
	@command -v "$(LINTER)" >/dev/null || { echo "monkey-c-linter was not found (install it with cargo or set LINTER=/path/to/monkey-c-linter)"; exit 1; }
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
	"$(FORMATTER)" source

format-check:
	"$(FORMATTER)" --check source

lint:
	"$(LINTER)" source

$(DEVELOPER_KEY):
	openssl genrsa -out $(DEVELOPER_KEY).pem 4096
	openssl pkcs8 -topk8 -inform PEM -outform DER -in $(DEVELOPER_KEY).pem -out $(DEVELOPER_KEY) -nocrypt
	$(RM) $(DEVELOPER_KEY).pem

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

build: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(MONKEYC)" -f monkey.jungle -d $(DEVICE) -o $(BIN_DIR)/mace-clubs.prg -y $(DEVELOPER_KEY)

test-build: $(DEVELOPER_KEY) | $(BIN_DIR)
	"$(MONKEYC)" -f monkey.jungle -d $(DEVICE) -o $(BIN_DIR)/mace-clubs-test.prg -y $(DEVELOPER_KEY) --unit-test

simulator-test: test-build
	"$(MONKEYDO)" $(BIN_DIR)/mace-clubs-test.prg $(DEVICE) -t

# Function coverage of the unit tests, via rafiki
# (https://github.com/bombsimon/monkey-c-rs). The test subcommand runs the
# whole pipeline: instrument into bin/coverage, compile, run in the
# simulator (starting it if needed), and print the report. `source` is
# passed explicitly so stale instrumented copies under build/ or tmp/ are
# never swept into the build.
coverage: $(DEVELOPER_KEY) | $(BIN_DIR)
	@command -v "$(RAFIKI)" >/dev/null || { echo "rafiki is not on PATH"; exit 1; }
	"$(RAFIKI)" coverage test -d $(DEVICE) -y $(DEVELOPER_KEY) --start-simulator source

clean:
	$(RM) $(BIN_DIR)/mace-clubs.prg $(BIN_DIR)/mace-clubs-test.prg
