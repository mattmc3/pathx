NIM ?= nim
NIMPRETTY ?= nimpretty
SRC := src/pathx.nim
TEST := tests/test_pathx.nim
BIN := bin/pathx

.PHONY: build test pretty

build: $(BIN)

$(BIN): $(SRC)
	mkdir -p bin
	$(NIM) c -d:release -o:$(BIN) $(SRC)

test:
	$(NIM) r $(TEST)

pretty:
	find src tests -name '*.nim' -print0 | xargs -0 $(NIMPRETTY) --backup:off
