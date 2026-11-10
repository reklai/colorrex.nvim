.PHONY: test unit conformance fault architecture integration reading servers e2e e2e-rex e2e-ghostty matrix docs verify

# NVIM is the binary the Neovim lanes run under; LUAJIT runs the pure ones.
NVIM ?= nvim
LUAJIT ?= luajit

# FILTER is a Lua pattern matched against test names.
test: unit conformance fault architecture integration

unit conformance fault architecture:
	$(LUAJIT) test/run.lua $@ "$(FILTER)"

integration:
	$(NVIM) --headless --clean -l test/run.lua integration "$(FILTER)"

# Meanings across languages. Lua and C always run; the rest run where their parsers
# are: an nvim-treesitter install, or COLORREX_PARSERS (a parser site) and
# COLORREX_QUERIES (a queries runtime). `make reading` regenerates the fixture the
# pure reading test uses, from test/support/snippets, with the same two variables.
reading:
	$(NVIM) --headless --clean -l test/support/tools/reading_fixture.lua

# What real language servers send for test/support/programs, recorded so the server
# test runs without them. Servers come from PATH or Mason, with the same two variables;
# COLORREX_RUST_SRC points rust-analyzer at a std source when the toolchain has none.
servers:
	$(NVIM) --headless --clean -l test/support/tools/server_fixture.lua

# Real Neovim in real terminals. Not part of `test`, and NVIM is the binary under
# test. e2e-rex runs from inside Rex; e2e-ghostty opens short-lived windows.
e2e: e2e-rex e2e-ghostty

e2e-rex:
	$(NVIM) -l test/e2e/rex.lua

e2e-ghostty:
	$(NVIM) -l test/e2e/ghostty.lua

# Every suite against several Neovims. VERSIONS are official releases, downloaded
# and run from a cache; set NVIMS to test binaries you already have instead.
matrix:
	sh test/matrix.sh

docs:
	$(NVIM) --headless --clean -c "helptags doc" -c "qall!"

verify: test e2e
