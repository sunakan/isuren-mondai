# NOTICE

## Official provenance

- repository: `https://github.com/isucon/isucon12-qualify.git`
- baseline commit: `95958774bde66d47fd26cc820fd2fbfbece798f1` (verified `origin` remote and clean worktree against `tmp/all-kakomon/isucon12-qualify` at implement time)
- license: MIT, `Copyright (c) 2022 ISUCON` (see `LICENSE` in this directory, copied byte-for-byte from the official baseline commit)

## What this directory contains (managed source, committed)

Code we build ourselves, taken as-is from the official baseline commit:

| path | official path | role |
| --- | --- | --- |
| `webapp/go/` | `webapp/go/` | Application (Echo, MySQL admin DB + SQLite tenant DB) |
| `blackauth/` | `blackauth/` | JWT-issuing auth server used for human/manual login flows |
| `bench/` | `bench/` | benchmark source (`cmd/bench/main.go` entrypoint) |
| `isucon12-portal/` | `isucon12-portal/` | Portal reporting client (`bench-tool.go`, `proto.go`) that `bench/go.mod` requires via a `replace ../isucon12-portal` directive. Committed here as-is; not a separate external clone despite the name — it is part of the isucon12-qualify tree itself. |
| `data/` | `data/` | offline benchmark fixture data generator that `bench/go.mod` requires via a `replace ../data` directive |

`webapp/go/go.mod`, `blackauth/go.mod`, `bench/go.mod`, `data/go.mod` are committed unchanged. `bench/go.mod`'s `replace` directives (`../isucon12-portal`, `../data`, `../webapp/go`) are preserved as-is; the provisioning build step stages these four directories as siblings before running `go build`, matching the official repository root layout.

### Intentionally excluded from this managed source tree

- `webapp/public.pem` (JWT public key) and `blackauth/isuports.pem` / `bench/isuports.pem` (identical JWT private key, embedded into the `blackauth` binary via `//go:embed`) are **not committed to this repository**. The official README documents them as one fixed key pair shared by every qualifier contestant (a public practice fixture, not a real secret), but per this repository's `NOTICE.md`/`recipe-contract.md` convention non-code key material is fetched at AMI-build time from the official exact commit and verified by checksum rather than stored in our Git history. See `kakomon12-qualify/provisioning/05-artifacts.sh`.
- `webapp/sql/**` (schema/seed SQL) is fetched at AMI-build time the same way, not committed here, per this repository's "非commitのSQL" convention.
- `public/` (prebuilt frontend static tree, produced by `frontend/vue.config.js`'s `outputDir: '../public'` and committed to the official repository) is fetched at AMI-build time, not committed here, per this repository's official-prebuilt-frontend convention (same policy as `kakomon9-qualify`).
- `initial_data/*.db` (per-tenant SQLite seed data), `bench/benchmarker.json` / `bench/benchmarker_tenant.json` (fixtures `bench/models.go` reads cwd-relative at runtime), and `webapp/sql/admin/90_data.sql` (gitignored upstream via `webapp/sql/admin/.gitignore`; a `mysqldump` seeding the ~100 baseline `tenant` rows, mounted as `docker-entrypoint-initdb.d` by the official `docker-compose.yml`) all ship only via the same GitHub Release asset (`bench/Makefile`'s `gh release download`), never as Git blobs in the official repository. They are fetched at AMI-build time with plain `curl` against the public `releases/download` URL (no `gh` CLI or token needed). The exact Release tag/asset name/SHA-256 were resolved during `verify` and are pinned in `kakomon12-qualify/scripts/artifact-inputs.env`.

## Local differences from the official baseline

None. All committed files are byte-for-byte copies of the official baseline commit (`rsync -a` from the exact-commit worktree-local mirror, only the key-material exclusions above applied). No source patches have been applied.

## Runtime identity mapping (isuren-mondai side, not part of this directory)

- account: official `isucon` → `isuren`
- hostnames: official `*.t.isucon.dev` / `admin.t.isucon.dev` → `*.t.isuren.internal` / `admin.t.isuren.internal` (`ISUCON_BASE_HOSTNAME` / `ISUCON_ADMIN_HOSTNAME` environment overrides; no source patch needed)
- webapp startup: official `docker compose -f docker-compose-go.yml up --build` (Type=simple, restart-always container) → native `go build` binary run directly under systemd, matching the `kakomon13`/`kakomon14` convention
