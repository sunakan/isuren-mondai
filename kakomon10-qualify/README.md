# kakomon10-qualify Go AMI recipe

This target packages the maintained Go Application and benchmark for the
ISUCON10 qualifier (ISUUMO, a real-estate/chair search site) as a single-node
practice image.

- official repository: `https://github.com/isucon/isucon10-qualify.git`
- official exact commit: `7e6b6cfb672cde2c57d7b594d0352dc48ce317df`
- local maintenance patches: `upstream/isucon10-qualify/NOTICE.md`

The audit checkout under `tmp/all-kakomon/` is never a build input.

## Contract

- OS: Ubuntu 26.04 LTS arm64 (exact base AMI ID:
  `ami-0b39c0e7d24a8c3db`; see `scripts/artifact-inputs.env`)
- region: `ap-northeast-1`
- Go (Application and benchmark): 1.26.6
- echo (webapp framework): v3.3.10+incompatible → `github.com/labstack/echo/v5`
  v5.3.1 (the official value is effectively obsolete; see NOTICE.md for the
  mechanical migration)
- MySQL: Ubuntu's `mysql-server` 8.4 series (the exact installed package
  version is recorded in `packages.tsv`; the 2026-08-18 component check used
  `8.4.10-0ubuntu0.26.04.1`). Official 5.7 is unavailable on this platform.
- Node.js (frontend build only, not installed on the AMI): 14.9.0
- frontend (Next.js/React/TypeScript/`@material-ui/core`): kept at the
  official version (9.4.2 / 16.13.1 / 3.9.3 / 4.9.14)
- public entrypoint: nginx `:80` (no hostname mapping; the official source
  has no competition domain reference to remap to `isuren.internal`)
- Application: `:1323` (official wildcard listen; nginx proxies to
  `127.0.0.1:1323`)
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

## Complete benchmark data and CI repair

The official generators produce 29,500 initial records, 500 verification
records (IDs 29501–30000), and 20 load-draft files of 500 records (IDs
30001–40000) for each of chair and estate. The first verification chair has
stock 1 for the sell-out check. `scripts/benchmark_data.py` checks all of
these inputs, both fixture JSON files, and all ten snapshot directories.
The same checker runs before Release packaging, on extraction and deployment,
and through Goss. The Go benchmark and its result semantics are unchanged.

The published `kakomon10-qualify-frontend-v1.0.0` archive omitted
`verify_draft_chair.txt` and `verify_draft_estate.txt`; the corrected recipe
rejects that incomplete archive. Its published bytes, tag, and digest remain
unchanged. A new Release is required before another AMI build.

For this omission, the target workflow's `workflow_dispatch` path performs a
CI-only data repair: choose a new, unused destination tag (for example
`kakomon10-qualify-frontend-v1.0.1`) and the existing archive's exact tag and
published SHA-256. Do not push the repair tag beforehand. The job runs the
whole official generator stream with Faker 4.1.1 and seed 19700101, then
requires the regenerated SQL, detail JSON, fixture JSON, and all load drafts
to match the existing Release byte for byte. A mismatch stops publication.
Only the two missing verification files and repair provenance are added;
frontend and snapshot files keep their original bytes. The manifest and
archive checksum are regenerated for the new Release. Node.js, Go, MySQL,
frontend build, and snapshot generation are skipped in this repair path.

Normal tag pushes still run the full build. Both paths serialize on the
destination tag and reject an already published Release before building;
repair also rejects an existing tag or the base tag as its destination.
After human-approved publication, verify the new API digest and manifest,
update `scripts/artifact-inputs.env` in a separate scoped commit, and push
that recipe commit before AMI verification. No unpublished digest is used.

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
4. `packer/kakomon10-qualify.pkr.hcl` waits for the completion marker and
   Goss result, checks the resolved Release identity, records verification
   logs on the build host, and runs `packer/seal-image.sh`. The sealed image
   keeps problem services enabled and stopped; cloud-init and MySQL
   regenerate instance identity on fresh boot.

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

## ARM64 AMI build

The repository implementation is complete; an AMI has not been built or
booted from this revision. Orb recipe/Golden/standalone, AMI build, AMI
fresh boot, and the 1bench-1web benchmark are separate `not-run` gates.

`scripts/artifact-inputs.env` owns the exact Tokyo-region base image,
Canonical owner/name, 8 GiB root volume, Packer network stack, and published
`kakomon10-qualify-frontend-v1.0.0` archive digest
`c47cced37f96028c7a48799a46dc9c84f3efddec37670889a43d069949d76d3c`.
This archive is 439,622,144 bytes, so download/extraction stay on the root
volume rather than `/tmp`. The 8 GiB volume is the base snapshot size;
10q's peak usage and remaining space must be measured in the fresh build.
There is no automatic OS, architecture, or disk-size fallback.

Before the build, commit and push the exact recipe revision and obtain
explicit approval for the EC2/AMI operation. The build task requires AWS
credentials for `ap-northeast-1`, Packer, Python with PyYAML, curl, jq, and
the existing `isuren-mondai-packer-network` stack. It reads VPC, subnet and
instance profile from the stack's Outputs; no resource IDs or caller
exports are needed. It checks the remote commit and public Release through
the anonymous GitHub API, and checks the fixed base image through AWS.

```bash
mise run kakomon10-qualify:validate
mise run kakomon10-qualify:build
```

The temporary build instance is `t4g.small`. AMI and snapshot tags record
architecture, exact recipe commit/tree, managed source tree, official
baseline, base image, plugin, Go, and frontend tag/digest. The AMI name is
`isuren/kakomon10-qualify-arm64-<UTC timestamp>Z`; a future AMD64 variant
will have its own image identity and validation.

## Seal and fresh boot

`packer/seal-image.sh` stops `isuumo-go`, nginx, and MySQL while retaining
their enabled state. It removes MySQL UUID and automatic TLS keys,
machine-id, SSH host keys, random seed, builder SSM state, login keys,
history, cloud-init instance cache/logs, and temporary source/data caches.
The official `env.sh` contains public practice DB defaults and is retained.

The persistent `/var/lib/isuren-mondai/kakomon10-qualify/recipe-ready`
records the verified recipe commit. If the old recipe User Data is supplied
again, it skips provisioning for that same commit and rejects another
commit. AWS cloud-init remains available for fresh SSH key generation and
new CFn role User Data. systemd regenerates machine-id; MySQL regenerates
server UUID/TLS material when the web role starts.

The installed read-only state checker has distinct `sealed`, `web`, and
`bench` states. Sealed checks run after cleanup in Packer. Fresh web checks
must also be run after reboot; compare machine-id, SSH key fingerprints,
and MySQL UUID between independently launched instances, and confirm
recipe-ready and data remain intact. This checks image state; lifecycle
benchmark/reset/recovery and SSM connectivity still require real runs.

```bash
sudo /usr/local/libexec/kakomon10-qualify-check-image-state web
```

## Standalone 1bench-1web

`cfn/kakomon10-qualify-1bench-1web.yaml` launches two `c8g.large` ARM64
instances with 30 GiB gp3 roots from the exact `AmiId` supplied by the
operator. Web is `10.42.1.11` and serves HTTP port 80; bench is
`10.42.1.10` and disables its local Application/nginx/MySQL. SSH uses
optional GitHub public keys; SSM access is supported by the instance role.
This is a standalone topology, separate from Portal/`isu` product gates.

After approval for the two instances, use the ARM64 AMI returned by the
build; do not substitute a base image or an AMD64 artifact.

```bash
AMI_ID='<EXACT_ARM64_AMI_ID_FROM_BUILD>'
aws cloudformation deploy --region ap-northeast-1 \
  --stack-name kakomon10-qualify-1bench-1web \
  --template-file cfn/kakomon10-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" \
  --capabilities CAPABILITY_IAM
```

CloudFormation completion alone does not prove successful User Data.
Confirm `cloud-init status --wait` and the relevant state checker on both
nodes. Connect to the bench as `isuren` and retain stdout/stderr separately:

```bash
cd /home/isuren/isuumo/bench
./bench --target-url http://10.42.1.11 >bench.stdout.jsonl 2>bench.stderr.log
tail -n 1 bench.stdout.jsonl | jq -e '.pass == true'
```

The benchmark initializes the web DB before each run. For a standalone
lifecycle gate, also collect a deliberate `pass:false` result (for example,
an unreachable target), then a normal result after recovery; verify
`POST /initialize`, normal benchmark, and both node roles again after
reboot. An exit code of zero from `bench` is never the pass oracle.

At the approved TTL, delete only this practice stack and verify its
instances/root volumes are gone. The shared Packer network is retained.

```bash
aws cloudformation delete-stack --region ap-northeast-1 \
  --stack-name kakomon10-qualify-1bench-1web
aws cloudformation wait stack-delete-complete --region ap-northeast-1 \
  --stack-name kakomon10-qualify-1bench-1web
```
