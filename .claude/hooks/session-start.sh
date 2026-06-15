#!/bin/bash
# SessionStart hook: make Claude Code on the web sessions build-ready.
#
# Installs the Gleam toolchain (fetched from GitHub, which is reachable) and
# downloads the library + demo dependencies. `gleam deps download` needs
# repo.hex.pm, which the default network policy blocks (see CLAUDE.md), so that
# step is fail-soft: even when it's blocked the hook still succeeds and
# `gleam format` (which needs no packages) works offline.
set -euo pipefail

# Only run in Claude Code on the web; locally the developer owns their toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GLEAM_VERSION="1.17.0"

# 1. Install Gleam if it isn't already present (idempotent; container state is
#    cached after the hook completes, so this normally runs once).
if ! command -v gleam >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/gleam.tar.gz" \
    "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz"
  tar xzf "$tmp/gleam.tar.gz" -C "$tmp"
  mv "$tmp/gleam" /usr/local/bin/gleam
  rm -rf "$tmp"
fi
gleam --version

# 2. Download Gleam dependencies for the library and the demo. Fail-soft: if
#    repo.hex.pm is blocked this prints a hint and the hook still exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}"
if gleam deps download; then
  (cd demo && gleam deps download) || true
else
  echo "session-start: 'gleam deps download' failed — is repo.hex.pm allowed?" >&2
  echo "session-start: skipping deps. 'gleam format' still works offline; the" >&2
  echo "session-start: full build runs in CI (.github/workflows/ci.yml)." >&2
fi
