# kakomon10-qualify Go AMI recipe

This target packages the maintained Go Application and benchmark for the
ISUCON10 qualifier (ISUUMO, a real-estate/chair search site) as a single-node
practice image.

- official repository: `https://github.com/isucon/isucon10-qualify.git`
- official exact commit: `7e6b6cfb672cde2c57d7b594d0352dc48ce317df`
- local maintenance patches: `upstream/isucon10-qualify/NOTICE.md`

The audit checkout under `tmp/all-kakomon/` is never a build input.

## Contract

- OS: Ubuntu 26.04 LTS arm64 (exact base AMI ID: not yet chosen; see
  `packer/README.md`)
- region: `ap-northeast-1`
- Go (Application and benchmark): 1.26.6
- echo (webapp framework): v3.3.10+incompatible → `github.com/labstack/echo/v5`
  v5.3.1 (the official value is effectively obsolete; see NOTICE.md for the
  mechanical migration)
- MySQL: `8.4.10-0ubuntu0.26.04.1` (the official `mysql-server-5.7` is not
  available for Ubuntu 26.04 arm64; see NOTICE.md)
- Node.js (frontend build only, not installed on the AMI): 14.9.0
- frontend (Next.js/React/TypeScript/`@material-ui/core`): kept at the
  official version (9.4.2 / 16.13.1 / 3.9.3 / 4.9.14)
- public entrypoint: nginx `:80` (no hostname mapping; the official source
  has no competition domain reference to remap to `isuren.internal`)
- Application: `127.0.0.1:1323`
- reset: `POST /initialize`

There is no `isuren.internal` hostname contract for this target: the audit
confirmed the official source has no `isucon.net`/`*.isucon.dev` reference
(the only domain-shaped string is a placeholder `isuumo@example.com` inside
the unused `agreed/` mock, which this recipe does not include). nginx serves
the default vhost.

## Topology boundary

The official contest separated 3 web nodes (1 core / 2 GiB) and 1 benchmark
node (1 core / 16 GiB), but the official `provisioning/ansible/allinone.yaml`
playbook and its `[allinone] 192.168.33.10` inventory already provide a
1-node reference configuration, and nginx's official config
(`proxy_pass http://localhost:1323`, no upstream pool) has no multi-node load
balancing to reproduce. This recipe follows that official allinone reference
and the kakomon12-qualify precedent: Application, MySQL, nginx, and the
benchmark binary all run on one image.

The official Go Application built at
`/home/isucon/isucon10-qualify/webapp/go/isuumo`, and the benchmark expects
to run from a `bench/` directory with `../initial-data` and `../webapp/fixture`
as siblings. This recipe preserves those relative paths under
`/home/isuren/isuumo/{webapp/go,bench,initial-data}`.

Run the benchmark as the practice user:

```bash
sudo -u isuren bash -c '
  cd /home/isuren/isuumo/bench
  exec ./bench --target-url http://127.0.0.1
'
```

`bench/` does not use isucandar (unlike KAKOMON12/13/14); its process always
exits 0 regardless of pass/fail (`bench/cmd/bench/bench.go` never calls
`os.Exit`). Callers must parse the final single-line JSON object
(`{"pass":bool,"score":int64,...}`) printed to stdout, not the exit code.

## Frontend and initial-data Release

Frontend source is not managed under `upstream/isucon10-qualify` (unlike the
Go Application and benchmark); it is fetched fresh at the exact official
commit by `scripts/build-frontend-release.sh`, which also runs the official
Faker-based dummy data generators (`initial-data/make_chair_data.py`,
`make_estate_data.py`) and the benchmark-verification snapshot generator
(`initial-data/make_verification_data`) against a throwaway MySQL + webapp
instance, then bundles the frontend static export, the two dummy-data SQL
files, the fixture JSON, and the bench result tree into one
`kakomon10-qualify-frontend-*` GitHub Release archive (tag prefix
`kakomon10-qualify-frontend-`). `provisioning/60-initdb.sh` and
`80-frontend.sh` fetch, checksum-verify, and place that single archive during
the AMI build; nothing is regenerated on every build.

This CI/Release build is Ubuntu 26.04 arm64-only: Node.js 14.9.0 has no
official `darwin-arm64` build (Node did not ship Apple Silicon builds until
v16), and the verification-snapshot step installs `mysql-server` via `sudo
apt-get`. It is not meant for interactive local runs on a development
machine; see `scripts/build-frontend-release.sh`'s header comment.

## Responsibilities

1. `cloud-init/` checks out the exact isuren-mondai commit and calls
   `provisioning/all.sh`.
2. `provisioning/10-base.sh`/`20-user.sh`/`30-runtime.sh`/`40-mysql.sh`
   install the pinned OS packages, contestant account, mise-managed Go, and
   MySQL 8.4.
3. `50-source.sh` deploys the managed webapp/bench/initial-data source tree.
   `60-initdb.sh` fetches and verifies the frontend Release archive, applies
   the official schema plus the frozen dummy data, and stages the bench
   result tree and fixture JSON. `70-webapp-go.sh` builds and starts the
   Application. `80-frontend.sh` places the already-verified frontend static
   export. `85-bench-build.sh` builds the benchmark binary. `90-nginx.sh`
   configures the public proxy. `99-verify.sh` runs Goss.
4. Packer (not yet authored this session; see `packer/README.md`) will wait
   for the completion marker and Goss result before sealing.

## Phase 1 verification (2026-08-18, aws-bastion EC2)

Before this recipe was written, every component above was validated by hand
on an aws-bastion Ubuntu 26.04 arm64 EC2 instance:

- webapp: builds with Go 1.26.6 and echo v5.3.1, connects to MySQL 8.4.10,
  and serves `/initialize`, chair/estate search, `/api/estate/nazotte`
  (MySQL `ST_Contains`/`ST_PolygonFromText`), and
  `/api/recommended_estate/:id` correctly
- bench: builds unmodified with Go 1.26.6 and reports
  `{"pass":true,"score":429,"messages":[],"reason":"OK","language":"go"}`
  against the webapp above
- MySQL: `mysql-server-5.7` is unavailable on Ubuntu 26.04 arm64
  (`apt-cache policy` only offers 8.4.x); `0_Schema.sql` applies unmodified
  to MySQL 8.4.10
- frontend: `npm ci && npm run build && npm run export` succeeds unmodified
  with Node.js 14.9.0 (official `linux-arm64` build)
- initial data: `make_chair_data.py`/`make_estate_data.py` (Faker 4.1.1) run
  unmodified under Python 3.14 and generate 29,500 SQL rows per table in
  under 11 seconds each

See `upstream/isucon10-qualify/NOTICE.md` for the exact evidence and
mechanical source changes.
