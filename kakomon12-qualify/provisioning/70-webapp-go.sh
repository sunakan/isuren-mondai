#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
WEBAPP_DIR="${ISUREN_HOME}/webapp/go"

# The official Application uses mattn/go-sqlite3, which requires CGO (see
# webapp/go.mod). This is the one component of this recipe not yet confirmed
# to build under Ubuntu 26.04 arm64 on real EC2/Packer hardware (this
# implement pass only ran on the local macOS worktree; see README.md). Do not
# set CGO_ENABLED=0 here even though other kakomonN targets do (their
# benchmarks/apps have no CGO dependency).
# webapp/go/isuports.go is `package isuports` (a library), not `package
# main`; the official entrypoint is cmd/isuports/main.go, matching the
# official Makefile's `go build -o isuports ./cmd/isuports`. Building `.`
# instead of `./cmd/isuports` was tried first and silently produced a Go
# package archive (ar format, not an ELF executable) named `isuports` with no
# execute bit -- `go build -o <name> .` only emits a binary when `.` is
# package main. chmod alone could not fix that; the fix is targeting the
# right package.
# shellcheck disable=SC2016 # positional parameter expands inside the child shell
runuser -u "${ISUREN_USER}" -- env HOME="${ISUREN_HOME}" CGO_ENABLED=1 MISE_BIN="${MISE_BIN}" \
  sh -c 'cd "$1" && "${MISE_BIN}" exec -- go build -trimpath -ldflags "-s -w" -o isuports ./cmd/isuports' \
  sh "${WEBAPP_DIR}"
chmod 0755 "${WEBAPP_DIR}/isuports"
test -x "${WEBAPP_DIR}/isuports"

install -m 0644 "${SCRIPT_DIR}/systemd/isuports-go.service" /etc/systemd/system/isuports-go.service
systemctl daemon-reload
systemctl enable isuports-go.service

log "70-webapp-go.sh: Application built (CGO_ENABLED=1) and service enabled"
