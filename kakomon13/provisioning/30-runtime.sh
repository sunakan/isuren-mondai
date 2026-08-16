#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

GO_VERSION="1.26.6"
GO_URL="https://dl.google.com/go/go1.26.6.linux-arm64.tar.gz"
GO_SHA256="d0507e9e9d7fe012aae570108cbd76c15de879e17130ab8cb90d4d7445cb1f2e"
GO_ROOT="/opt/go-${GO_VERSION}"

grep -qF "go = \"${GO_VERSION}\"" "${SCRIPT_DIR}/mise.ami.toml"
grep -qF "checksum = \"sha256:${GO_SHA256}\"" "${SCRIPT_DIR}/mise.ami.lock"
grep -qF "url = \"${GO_URL}\"" "${SCRIPT_DIR}/mise.ami.lock"

if [ ! -x "${GO_ROOT}/bin/go" ]; then
  archive="$(mktemp)"
  staging="$(mktemp -d)"
  trap 'rm -f "${archive}"; rm -rf "${staging}"' EXIT
  curl -fsSL "${GO_URL}" -o "${archive}"
  echo "${GO_SHA256}  ${archive}" | sha256sum -c -
  tar -xzf "${archive}" -C "${staging}"
  mv "${staging}/go" "${GO_ROOT}"
fi
ln -sfn "${GO_ROOT}/bin/go" /usr/local/bin/go
ln -sfn "${GO_ROOT}/bin/gofmt" /usr/local/bin/gofmt

test "$(/usr/local/bin/go version)" = "go version go${GO_VERSION} linux/arm64"
log "30-runtime.sh: done"
