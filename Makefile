DEVICE ?= instinct3solar45mm
DEVELOPER_KEY ?= developer_key.der
BIN_DIR ?= bin
TOOL_RESOLVER := node tools/resolve-tool.js
JAVA ?= $(shell $(TOOL_RESOLVER) java)
MONKEYC ?= $(shell $(TOOL_RESOLVER) monkeyc)
MONKEYDO ?= $(shell $(TOOL_RESOLVER) monkeydo)
FORMATTER ?= $(shell $(TOOL_RESOLVER) monkey-c-formatter)
LINTER ?= $(shell $(TOOL_RESOLVER) monkey-c-linter)
RAFIKI ?= $(shell $(TOOL_RESOLVER) rafiki)
JAVA_PATH := $(if $(findstring /,$(JAVA)),$(dir $(JAVA)):,)
export PATH := $(JAVA_PATH)$(PATH)

.PHONY: check pre-commit install-hooks doctor tool-resolver-test xml fit-schema format format-check lint build test-build simulator-test coverage clean

check: doctor tool-resolver-test xml fit-schema format-check lint build test-build

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

tool-resolver-test:
	node --test tools/resolve-tool.test.js

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
