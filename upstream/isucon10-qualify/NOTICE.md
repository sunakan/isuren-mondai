# isucon10-qualify managed source NOTICE

- Official repository: https://github.com/isucon/isucon10-qualify.git
- Official exact commit: `7e6b6cfb672cde2c57d7b594d0352dc48ce317df`
  (2021-01-29, "fix: deno type (#183)"; the repository's default-branch tip)
- License: MIT (`LICENSE`; Copyright (c) 2020 isucon10-qualify)

This directory is the Go Application, Go benchmark, and initial-data generator
maintained by isuren-mondai for the ISUCON10 qualifier (ISUUMO). It is not a
byte-for-byte mirror of the official commit above. The local audit checkout
under `tmp/all-kakomon/isucon10-qualify` is provenance evidence only and is
never a build input.

## Managed paths

- `webapp/go/{main.go,go.mod,go.sum}` (the only Go implementation kept;
  `deno/`, `nodejs/`, `perl/`, `php/`, `python/`, `ruby/`, `rust/` are excluded
  per the isuren-mondai policy of Go-only ports)
- `webapp/mysql/db/{0_Schema.sql,init.sh}`
- `webapp/fixture/` (placeholder only; the actual
  `chair_condition.json`/`estate_condition.json` are Faker-generated output,
  see below)
- `bench/{asset,client,cmd,fails,parameter,reporter,scenario,score,go.mod,go.sum}`
- `initial-data/{make_chair_data.py,make_estate_data.py,requirements.txt,description.txt,make_verification_data}`
  (**not** `initial-data/origin`; see "Source and assets intentionally not
  managed here" below)

Excluded on purpose:

- `agreed/` (a Node.js mock mail-approval server). Audited and confirmed
  unreferenced by both the Go webapp and `bench/` (`postEstateRequestDocument`
  only validates the `email` field in the request body and never calls out to
  this service).
- container-only `Dockerfile`/`Makefile`/`.gitignore` files under `webapp/go`
  and `bench` (builds go through `mise exec -- go build`, not `make`/Docker)
- `provisioning/ansible/**` (isuren-mondai replaces Ansible with
  `kakomon10-qualify/provisioning/*.sh` + cloud-init, per repository policy)

## Local maintenance changes (`webapp/go/main.go`)

The official `webapp/go` targets Go 1.14 and `github.com/labstack/echo`
v3.3.10+incompatible. isuren-mondai's runtime policy fixes Go at 1.26.6 for
both the Application and benchmark; echo v3 is effectively obsolete, so this
target upgrades to echo v5 (`github.com/labstack/echo/v5` v5.3.1, the latest
tagged release verified against Go 1.26.6 on 2026-08-18 aws-bastion
experimentation). The migration required only mechanical API updates; no
handler logic, SQL, or route changed:

- import path: `github.com/labstack/echo{,/middleware}` →
  `github.com/labstack/echo/v5{,/middleware}`
- handler signature: `func handler(c echo.Context) error` →
  `func handler(c *echo.Context) error` (echo v5 makes `Context` a concrete
  struct instead of an interface)
- `e.Debug = true` + `e.Logger.SetLevel(log.DEBUG)` → construct
  `e.Logger = slog.New(slog.NewTextHandler(...))` directly (echo v5 replaces
  the gommon `Logger` interface with `log/slog`, and drops `Echo.Debug`)
- `middleware.Logger()` → `middleware.RequestLogger()` (renamed in v5)
- `echo.Map{}` → `map[string]any{}` (the `echo.Map` type alias was removed)
- `e.Logger.Fatalf(...)` / `e.Logger.Fatal(e.Start(...))` → `log.Fatalf(...)`
  from the standard library (`slog.Logger` has no `Fatal*` helpers)
- `c.Logger().Errorf(...)` / `c.Echo().Logger.Errorf(...)` (and the `Infof`
  equivalents) → small `logErrorf`/`logInfof` wrapper functions that call
  `fmt.Sprintf` then `slog.Logger.Error`/`Info` (`slog.Logger` has no
  printf-style helpers; the wrappers keep every call site's message text
  unchanged instead of rewriting ~50 log call sites into structured
  key-value logging)
- one log message in `searchEstateNazotte`
  (`"select * from estate where latitude ..."`, no `%v` verb despite being
  passed the query error as an argument) gained an explicit `%v` verb so the
  error text is actually logged; this is the only observable log-text change,
  surfaced by `go vet`'s printf checker rejecting the mechanically renamed
  `logInfof` call

`go.mod`'s `go` directive was bumped from `1.14` to `1.25.0` by `go mod tidy`
during the same migration; the toolchain used for every build in this
recipe is still the pinned 1.26.6.

Verified 2026-08-18 on an aws-bastion Ubuntu 26.04 arm64 EC2 instance: the
migrated webapp builds and serves `/initialize`, chair/estate search,
`/api/estate/nazotte` (MySQL `ST_Contains`/`ST_PolygonFromText` spatial
query), and `/api/recommended_estate/:id` correctly against MySQL 8.4.10 with
Faker-generated dummy data (29,500 rows per table). The official Go
benchmark (`bench/`) required **no source changes** and reported
`{"pass":true,"score":429,...}` against this webapp.

## MySQL version

The official `mysql-server-5.7` package is not available for Ubuntu 26.04 LTS
arm64 (`apt-cache policy mysql-server` only offers `8.4.10-0ubuntu0.26.04.1`
and `8.4.8-0ubuntu1` on this release). This target uses MySQL
`8.4.10-0ubuntu0.26.04.1`. `webapp/mysql/db/0_Schema.sql` required no changes
(no MySQL 5.7-only syntax, no spatial-index/engine clauses); the DB user
created by provisioning uses MySQL 8.4's default `caching_sha2_password`
auth plugin, which `go-sql-driver/mysql` v1.5.0 (pinned by `go.mod`, kept
unchanged from the official value) supports without modification.

## Node.js version (frontend build only; not part of this managed tree)

Frontend source (`webapp/frontend`) is intentionally **not** copied into
`upstream/isucon10-qualify` (see `kakomon10-qualify/scripts/build-frontend-release.sh`
and its own official-source fetch instead). The official competition
provisioning (`provisioning/ansible/roles/langs/tasks/main.yaml`, "Install
Node v14.9.0") installs Node.js 14.9.0 via xbuild and uses it to build the
frontend; `webapp/frontend/Dockerfile`'s `node:12.17` base image is a
Docker-only local-dev path and is not the competition value. This target
follows the actual competition provisioning value: Node.js 14.9.0. Verified
2026-08-18: Node.js 14.9.0 ships an official `linux-arm64` build
(`https://nodejs.org/dist/v14.9.0/node-v14.9.0-linux-arm64.tar.gz`,
sha256 `6619a69ffe95c602105484bdecbdccb319e1c0db861203bffb9b6aedfae2c2df`);
`npm ci && npm run build && npm run export` succeeded unmodified against the
official `package.json` (Next.js 9.4.2, React 16.13.1, TypeScript 3.9.3,
`@material-ui/core` 4.9.14 — all kept at the official version per
repository policy). There is no official `darwin-arm64` build for Node.js
14.9.0 (Node.js did not ship Apple Silicon builds until v16), so the
frontend Release build only targets `linux-arm64` (the CI runner
architecture, matching the AMI); it cannot run natively on an Apple Silicon
development Mac.

## Source and assets intentionally not managed here

Two inputs are official (from the exact commit above) but are **not**
committed under `upstream/isucon10-qualify`, regardless of whether the
official repository itself commits them: image/binary assets and non-Go
frontend source are kept out of isuren-mondai's Git history entirely, and are
instead fetched at build time from the exact official commit, then
checksum/tree-verified before use.

- `webapp/frontend` (Next.js/React/TypeScript source). Fetched by
  `kakomon10-qualify/scripts/build-frontend-release.sh` via a blobless
  `git sparse-checkout` of the official repository at
  `7e6b6cfb672cde2c57d7b594d0352dc48ce317df`, then verified by comparing the
  checked-out `HEAD` against that exact commit before building.
- `initial-data/origin/{chair,estate}/*.png` (6 seed images used by the Faker
  generators below; they are official committed assets, not generated
  output, but per repository policy — see
  `.agents/skills/orchestrate-kakomon-ami-sessions/SKILL.md` — image/binary
  files never enter this project's Git management regardless of their
  official provenance or size). Fetched by the same sparse checkout
  (`git sparse-checkout set --cone webapp/frontend initial-data/origin`) and
  verified against `kakomon10-qualify/scripts/frontend-assets.manifest.sha256`
  (6 SHA-256 entries, computed from the worktree-local official mirror at the
  same exact commit) before the Faker generators consume them. Verified
  2026-08-18: this fetch-and-verify step was tested standalone on an
  aws-bastion EC2 instance; all 6 files matched the manifest.

## Non-commit data (Faker-generated dummy data and images)

`initial-data/make_chair_data.py` and `make_estate_data.py` (Faker, seeded
deterministically with `19700101`) generate `webapp/mysql/db/{1_DummyEstateData.sql,2_DummyChairData.sql}`,
`webapp/fixture/{chair_condition.json,estate_condition.json}`, and 1,000
recolored copies each of the fetched `initial-data/origin/{chair,estate}/*.png`
into `webapp/frontend/public/images/{chair,estate}/`. None of this generated
output is committed to Git (`webapp/mysql/.gitignore`,
`initial-data/.gitignore` already exclude it upstream); per the plan decision
recorded in `aws-bastion/isuren-mondai/tmp/kakomon10-qualify-plan.md` §0, this
target generates it once during the frontend Release CI build
(`kakomon10-qualify/scripts/build-frontend-release.sh`, Python 3 + Faker
4.1.1 from `requirements.txt`, unmodified) and freezes the result inside the
same `kakomon10-qualify-frontend-*` GitHub Release archive that carries the
built frontend static export, instead of regenerating it on every AMI build.
Verified 2026-08-18: both generators ran unmodified under Python 3.14 in
under 11 seconds each and produced 29,500 SQL rows per table.

## `bench/` result contract

`bench/` does not use isucandar (unlike KAKOMON12/13/14); it is a small
custom benchmarker (`morikuni/failure`, `google/go-cmp`, `google/uuid`,
`golang.org/x/sync` only). `bench/cmd/bench/bench.go`'s `main()` never calls
`os.Exit`, so the process always exits 0 regardless of pass/fail; the
authoritative result is the single-line JSON object
(`{"pass":bool,"score":int64,"messages":[...],"reason":string,"language":string}`)
that `bench/reporter/reporter.go` prints to stdout. Callers must parse that
JSON, not the process exit code.
