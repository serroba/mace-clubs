DEVICE ?= instinct3solar45mm
DEVELOPER_KEY ?= developer_key.der
BIN_DIR ?= bin
MONKEYC ?= monkeyc
MONKEYDO ?= monkeydo

.PHONY: check doctor xml format format-check lint build test-build simulator-test clean

check: doctor xml format-check lint build test-build

doctor:
	@command -v java >/dev/null || { echo "java is not on PATH"; exit 1; }
	@command -v "$(MONKEYC)" >/dev/null || { echo "monkeyc is not on PATH (or set MONKEYC=/path/to/monkeyc)"; exit 1; }
	@command -v monkey-c-formatter >/dev/null || { echo "monkey-c-formatter is not on PATH"; exit 1; }
	@command -v monkey-c-linter >/dev/null || { echo "monkey-c-linter is not on PATH"; exit 1; }
	@command -v xmllint >/dev/null || { echo "xmllint is not on PATH"; exit 1; }

xml:
	@find . -name '*.xml' -not -path './.git/*' -print0 | xargs -0 -n1 xmllint --noout

format:
	monkey-c-formatter source

format-check:
	monkey-c-formatter --check source

lint:
	monkey-c-linter source

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

clean:
	$(RM) $(BIN_DIR)/mace-clubs.prg $(BIN_DIR)/mace-clubs-test.prg
