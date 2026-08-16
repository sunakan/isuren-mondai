# Source audit

Evidence was read from the official repository at the two full commit IDs; the
local audit checkout is not a build source.

## Original to maintained

`34b3e785ebdd97d5c39a1263cbf56d1ae5e3ef91` used Go 1.12 in both modules.
`ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0` declares Go 1.23 for the
benchmark and Go 1.25 for the Application, updates their dependencies and HTTP
stack, removes the pre-Go-1.13 benchmark session file, updates random APIs, and
moves the shipment mock from port 7000 to 7001. Across `go.mod`, `go.sum`,
`cmd/bench`, `bench`, and `webapp/go`, the official diff is 26 files with 329
insertions and 221 deletions (including container-only files excluded here).

Both managed modules pass `go test ./...` with Go 1.26.6. No older Go fallback
is implemented. A future incompatibility is a component-specific stop gate.

## Local patch boundary

Compared with the maintained commit, executable Go source has exactly three
intentional changes:

1. benchmark target URL and Host use `isucon9.isuren.internal`;
2. the Application binds to `127.0.0.1:8000`;
3. `POST /initialize` propagates failure from `../init.sh`.

Dockerfiles, helper container scripts, the Portal benchmark worker,
development standalone mocks, frontend source, SQL, initial data, and built
frontend bytes are excluded from the managed tree. Their responsibilities and
exact direct-fetch paths are recorded in `NOTICE.md` and the target artifact
manifest.

## Result semantics and topology

The official benchmark prints its final `{pass,score,campaign,language,messages}`
JSON to stdout. Declared benchmark failures still return process exit code 0,
and the recipe intentionally adds no wrapper. Operators and product-level
callers must treat the last JSON object as authoritative instead of equating
process exit 0 with benchmark success.

The official contest responsibility boundary was Web1 plus Bench1. The recipe
is deliberately a one-VM practice topology: MySQL, Go Application, nginx,
benchmark binary, and benchmark assets coexist. Payment and shipment mocks are
created by the benchmark process on loopback and are absent otherwise. This is
not evidence that official multi-node or Orb topology has been reproduced.

`POST /initialize` is the reset contract. systemd boot enablement and
`Restart=on-failure` cover service recovery and reboot startup. The precise
official restart command/API remains unconfirmed and is not implemented.
