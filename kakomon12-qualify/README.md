# kakomon12-qualify Go AMI recipe

This target packages the Go Application, `blackauth` auth server, and
benchmark for the ISUCON12 qualifier as a single-node practice image.

- official repository: `https://github.com/isucon/isucon12-qualify.git`
- official baseline commit: `95958774bde66d47fd26cc820fd2fbfbece798f1`

The audit checkout under `tmp/all-kakomon/` is never a build input.

## Contract

- OS: Ubuntu 26.04 LTS arm64, same base AMI as kakomon9-qualify/kakomon13/kakomon14
- Go: 1.26.6 for Application, auth server, and benchmark
- public hostname: wildcard `*.t.isuren.internal` (nginx `server_name`, TLS SAN)
- admin hostname: `admin.t.isuren.internal`
- nginx: port 443 only (the official recipe has no port-80 vhost either)
- Application (`isuports-go.service`): `127.0.0.1:3000`
- Auth server (`blackauth.service`): `127.0.0.1:3001`
- admin DB: MySQL `isuports` (user `isucon`/`isucon`, matching the official
  `docker-compose-go.yml` public practice defaults)
- tenant DB: one SQLite file per tenant under `/home/isuren/webapp/tenant_db/`
- reset: `POST /initialize`, implemented by the official `webapp/sql/init.sh`
  (re-applies `init.sql`, re-copies `initial_data/*.db` into `tenant_db/`)

## Why this recipe needs no dynamic DNS (unlike kakomon13)

isucon12-qualify's benchmarker separates its actual TCP destination from the
HTTP Host header/TLS SNI it sends (`bench/option.go`'s `Option.TargetAddr`):
when `-target-addr host:port` is given, every connection dials that address
directly while `req.Host`/SNI still carry whatever `-target-url` says. The
Application itself only compares the Host header against
`ISUCON_BASE_HOSTNAME`/`ISUCON_ADMIN_HOSTNAME` (both are plain environment
variables, `webapp/go/isuports.go`'s `getEnv(...)` calls -- no source patch
needed). So a 1bench-1web split only needs:

- `-target-addr <web1 private IP>:443` (bench dials Web directly)
- `-target-url https://admin.t.isuren.internal` or any `*.t.isuren.internal`
  name (Host header / SNI only)
- nginx's `server_name *.t.isuren.internal;` matches every tenant subdomain
  without per-subdomain DNS records

This means no PowerDNS, no `/etc/hosts` rewriting, and no per-clone runtime
identity generation are needed at all -- everything in this recipe (including
the wildcard TLS certificate) can be fixed once at AMI build time. This is a
meaningful simplification versus kakomon13, whose benchmarker instead does
real DNS resolution of many generated subdomains (`dnsRecordPretest`) and
therefore needs a PowerDNS zone regenerated with the clone's own address on
every fresh boot.

## TLS

A self-signed wildcard certificate (`CN=t.isuren.internal`, SAN
`DNS:t.isuren.internal,DNS:*.t.isuren.internal`) is generated once during
provisioning (`90-nginx.sh`) and intentionally retained in the sealed image,
plus registered with the OS trust store (`update-ca-certificates`), following
the same precedent kakomon13 already established (documented there as
matching the official ISUCON13 operator practice of shipping one shared
wildcard certificate to every contestant). It is a public practice fixture
for a single time-boxed competition over dummy data; it must never be reused
for mTLS, Portal authentication, credentials, or trusted production traffic.

## JWT key pair

`webapp/public.pem` (public key, loaded by the Application at runtime) and
`blackauth/isuports.pem` (private key, embedded into the `blackauth` binary
at compile time via `//go:embed`, and byte-identical to `bench/isuports.pem`
in the official tree) are documented by the official README as one fixed key
pair shared by every qualifier contestant -- a public practice fixture, not a
per-contestant secret. Per the human decision recorded for this recipe, they
are fetched from the official exact commit and baked into the AMI the same
way the TLS certificate is. They are **not committed to this Git repository**
(see `upstream/isucon12-qualify/NOTICE.md`); `provisioning/05-artifacts.sh`
fetches and checksums them at AMI-build time instead.

## Result contract (differs from kakomon9-qualify/kakomon13/kakomon14)

Unlike this repository's other targets, isucon12-qualify's official
benchmarker (`bench/cmd/bench/main.go`) does **not** print a JSON object to
stdout by default. It logs human-readable lines such as `PASSED: true` /
`SCORE: <n>` via its own logger, and only sends a structured
`isuxportalResources.BenchmarkResult` protobuf when the
`ISUXBENCH_REPORT_FD` environment variable is set (i.e. only when run under
the ISUCON Portal). `-exit-error-on-fail` makes the process exit non-zero on
failure; without it, a failing run can still exit 0. Per the human decision
recorded for this recipe, **this recipe does not add a wrapper to translate
this into the JSON contract used elsewhere in this repository** -- callers
must read the benchmarker's own stdout/stderr log and honor
`-exit-error-on-fail`, not assume a `{"pass":...}` line exists.

```text
/home/isuren/bench \
  -target-url https://admin.t.isuren.internal \
  -target-addr WEB_PRIVATE_IP:443 \
  -exit-error-on-fail \
  -duration 60s
```

## Topology boundary

The official contest separated Web (×3, `c5.large`) from a dedicated
Fargate-hosted Bench. This recipe places the Application, MySQL, nginx, and
`blackauth` on one common image for personal practice; the image itself
carries no role assignment (kakomon13/kakomon14 pattern). A later
CloudFormation stack selects roles, matching `cfn/kakomon14-1bench-1web.yaml`
and `cfn/kakomon13-1bench-1web.yaml`; there is no kakomon12-qualify cfn
template yet (out of scope for this implement pass).

The official `/etc/hosts`-based inter-node addressing used by the 3-node
canonical topology is not reproduced in this image (see "Why this recipe
needs no dynamic DNS" above) -- neither the wildcard nginx `server_name` nor
the benchmarker's `-target-addr`/Host-header split requires it.

## Responsibilities

1. `cloud-init/` checks out the exact isuren-mondai commit and calls
   `provisioning/all.sh`.
2. `provisioning/10-base.sh` installs OS packages, including the
   `build-essential` CGO toolchain `webapp/go`'s `mattn/go-sqlite3` dependency
   needs. `provisioning/05-artifacts.sh` fetches every official non-code input
   (`webapp/sql/`, the JWT key pair, the prebuilt `public/` frontend tree,
   and the `initial_data` GitHub Release, the latter via plain `curl` against
   the public `releases/download` URL -- no `gh` CLI or token needed) at its
   exact commit/tag and verifies tree/manifest/SHA-256 identities inside the
   AMI build.
3. `provisioning/` installs the runtime and services, deploys the verified
   inputs to their official relative paths (`/home/isuren/webapp/**`,
   `/home/isuren/blackauth/**`, `/home/isuren/bench`), builds
   Application/auth-server/benchmark, and runs Goss.
4. Packer waits for the completion marker and seals clone-local identity
   (machine-id, SSH host keys, `authorized_keys`). It does not upload local
   `dist/`; AMI build, fresh-boot, benchmark, Orb, and AWS product gates
   remain separate.

## Frontend

Frontend source is not managed and Node.js/npm are not installed, matching
the `kakomon9-qualify` convention. The official repository's
`frontend/vue.config.js` sets `outputDir: '../public'`, and the resulting
`public/` tree (7 files: `index.html`, `favicon.ico`, hashed `css/`/`js/`
bundles, two `img/` assets) is committed to the official repository
byte-for-byte (confirmed via `git ls-files public/` against the official
mirror, not gitignored). Provisioning fetches that exact tree from the
official commit during the AMI build; there is no local `dist/` and no
frontend Release workflow for this target.

## Known gaps for the `verify` phase (this implement pass could not resolve them)

This recipe was written and reviewed on a local macOS worktree only, without
network access to GitHub Releases or a real Ubuntu 26.04 arm64 EC2/Packer
build (both are out of scope for `onboard-kakomon-ami-recipe`'s
audit/plan/implement modes; they belong to `verify`). Before building this
AMI:

1. **Resolved during `verify`.** `kakomon12-qualify/scripts/artifact-inputs.env`'s
   `INITIAL_DATA_RELEASE_TAG` / `INITIAL_DATA_ASSET_NAME` / `INITIAL_DATA_SHA256`
   are now pinned to the release tagged `Latest` by
   `https://github.com/isucon/isucon12-qualify/releases` (asset
   `initial_data.tar.gz`; the human downloaded it via the GitHub web UI and
   this session independently re-hashed the same file). `bench/Makefile`
   itself fetches this asset via a floating `gh release list | awk
   '/Latest/{print $3}' | xargs gh release download` selector with no
   committed Git blob; this recipe pins the resolved identity instead.
   `05-artifacts.sh` fetches it with plain `curl` against
   `github.com/.../releases/download/<tag>/<asset>` (no `gh` CLI or GitHub
   token needed, since `isucon/isucon12-qualify` is a public repository --
   same precedent as kakomon14/13's frontend Release fetch). During this
   resolution, this sandbox's `gh`/`ghtkn` token could list releases via
   GraphQL (`gh release list`) but got 403/"release not found" on the REST
   `releases/tags` and `release download` endpoints; plain `curl` against the
   public download URL worked without any token.
2. **The internal layout of the `initial_data` archive past `initial_data/*.db`
   was not confirmed.** `bench/Makefile` also has targets named
   `benchmarker.json`/`benchmarker_tenant.json` that depend on the same
   archive; `05-artifacts.sh` only asserts `initial_data/*.db` exists after
   extraction and does not (cannot, without downloading it) place any other
   file the archive might contain relative to `bench/`.
3. **Whether the initial ~100 tenant rows referenced by
   `init.sql`'s `DELETE FROM tenant WHERE id > 100` come from inside that
   archive (e.g. an admin-DB SQL dump alongside the per-tenant `.db` files)
   or are created by the benchmarker's own prepare phase
   (`-prepare-only`/`-skip-prepare` flags) was not confirmed.** See the note
   in `provisioning/60-initdb.sh`.
4. **`webapp/go`'s CGO dependency (`mattn/go-sqlite3`) has not been built on
   real Ubuntu 26.04 arm64.** `provisioning/70-webapp-go.sh` sets
   `CGO_ENABLED=1` and `10-base.sh` installs `build-essential`, but this was
   only reasoned about from `go.mod`/the official `Dockerfile`
   (`apt-get install -y wget gcc g++ make sqlite3`), not verified on
   arm64 hardware. This is the most likely source of a Red result in the
   `verify` phase's first Packer build.
5. **The `data/` Go module's role was not fully traced.** `bench/go.mod`
   requires `github.com/isucon/isucon12-qualify/data` directly (not just
   transitively); `data/cmd/builder/main.go` looks like an offline fixture
   generator, but whether `bench`'s runtime scenario code actually calls into
   `data` at benchmark-run time (as opposed to only at compile time via an
   unused import) was not traced line-by-line.
6. **`redis-server` is intentionally excluded from this recipe** (confirmed:
   no reference in `webapp/go`, `blackauth`, or `bench` source, nor in either
   module's `go.mod`/`go.sum`; it comes from
   `provisioning/mitamae/cookbooks/redis/default.rb` in the official
   repository with no other apparent purpose). Human-confirmed decision, not
   a gap, but recorded here in case verify-phase behavior suggests otherwise.

No `mise-tasks/kakomon12-qualify/prepare-artifacts` or
`verify-artifacts`/`audit-upstream-update` tasks exist yet (unlike
kakomon9-qualify): this recipe fetches and verifies its non-code inputs
directly inside `provisioning/05-artifacts.sh` during the AMI build rather
than via a separate host-side staging script, closer to kakomon13's
`50-source.sh` pattern. A `refresh-upstream`-equivalent task for auditing
future upstream commits does not exist yet either.
