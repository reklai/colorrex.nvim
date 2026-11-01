#!/bin/sh
# Every suite, against every Neovim. From inside Rex, on a desktop session:
#
#   make matrix                        downloads official releases, then tests them
#   VERSIONS="v0.12.0 nightly" make matrix
#   NVIMS="/usr/bin/nvim" make matrix  tests binaries you already have, no download
#
# Releases go to the cache, not this repository. Anything below 0.12 must refuse
# cleanly, so that is what gets tested for it.
set -u

VERSIONS=${VERSIONS:-v0.11.7 v0.12.0 stable nightly}
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/color-rex/nvim
case $(uname -m) in
  aarch64 | arm64) ARCH=arm64 ;;
  *) ARCH=x86_64 ;;
esac

fetch() {
  dir=$CACHE/$1
  case $1 in
    stable | nightly) rm -rf "$dir" ;; # these move, so a cached copy goes stale
  esac
  if [ ! -x "$dir/nvim-linux-$ARCH/bin/nvim" ]; then
    mkdir -p "$dir"
    curl -fsSL "https://github.com/neovim/neovim/releases/download/$1/nvim-linux-$ARCH.tar.gz" |
      tar xz -C "$dir" || return 1
  fi
  echo "$dir/nvim-linux-$ARCH/bin/nvim"
}

if [ -z "${NVIMS:-}" ]; then
  NVIMS=
  for version in $VERSIONS; do
    binary=$(fetch "$version") || { echo "could not fetch $version"; exit 1; }
    NVIMS="$NVIMS $binary"
  done
fi

status=0
for binary in $NVIMS; do
  version=$("$binary" --version | head -1)
  supported=$("$binary" --headless --clean -c 'lua io.stdout:write(tostring(vim.fn.has("nvim-0.12")))' -c 'qa!')
  echo "=== $version"
  if [ "$supported" != "1" ]; then
    "$binary" --headless --clean --cmd "set rtp^=$PWD" -c 'runtime plugin/color-rex.lua' -c 'colorscheme color-rex' \
      -c 'lua io.stdout:write("\nexists=" .. vim.fn.exists(":ColorRex"))' -c 'qa!' 2>&1 | grep -q 'requires Neovim 0.12' &&
      echo "ok    refuses cleanly" || { echo "FAIL  no clean refusal"; status=1; }
    continue
  fi
  for target in integration e2e-rex e2e-ghostty; do
    output=$(make --no-print-directory "$target" NVIM="$binary" 2>&1)
    code=$?
    echo "$output" | grep -E '^(FAIL|SKIP|ERROR)' | cut -c1-110
    printf '%-13s %s\n' "$target" "$(echo "$output" | tail -1 | cut -c1-60)"
    [ $code -eq 0 ] || status=1
  done
done
exit $status
