# kakomon9-qualify Go AMI recipe

This target packages the maintained Go Application and benchmark for the
ISUCON9 qualifier as a single-node practice image. It deliberately separates
three identities:

- official historical source: `34b3e785ebdd97d5c39a1263cbf56d1ae5e3ef91`
- official maintained baseline: `ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0`
- local maintenance patches: `upstream/isucon9-qualify/NOTICE.md`

The audit checkout under `tmp/all-kakomon/` is never a build input.

## Contract

- OS: Ubuntu 26.04 LTS arm64, Canonical release serial `20260806`
- base AMI: `ami-0df1235688731e6cc` in `ap-northeast-1`
- Go: 1.26.6 for both Application and benchmark
- public hostname: `isucon9.isuren.internal`
- nginx: ports 80 and, when the public test fixture is enabled, 443
- Application: `127.0.0.1:8000`
- benchmark-owned payment mock: `localhost:5555`
- benchmark-owned shipment mock: `localhost:7001`
- reset: `POST /initialize`

The base ID and release serial come from Canonical's released Ubuntu EC2 image
locator (`https://cloud-images.ubuntu.com/locator/ec2/releasesTable`) and are
frozen in Packer; there is no AMI search or `most_recent` fallback. The Amazon
Packer plugin is exactly 1.8.2. The image records the installed OS package
versions in durable provenance.

The exact ISUCON restart command/API is not implemented because its contract
has not been confirmed. Starting or stopping `isucari-go.service` is an
operator action, not a claimed contest restart implementation.

The hostname inventory is explicit; only the Application names are served by
nginx. Payment and shipment names are loopback-resolved for traceability, but
the fixed benchmark contract still uses `localhost:5555` and `localhost:7001`
and owns those listeners only for the duration of a run.

| Official hostname | Private mapping | Recipe role |
| --- | --- | --- |
| `isucon9.catatsuy.org` | `isucon9.isuren.internal` | canonical Application name |
| `isucari.t.isucon.pw` | `isucari.t.isuren.internal` | Application compatibility name |
| `payment.isucon9q.catatsuy.org` | `payment.isucon9q.isuren.internal` | historical payment name |
| `payment.t.isucon.pw` / `bp.t.isucon.pw` | `payment.t.isuren.internal` / `bp.t.isuren.internal` | maintained payment names |
| `shipment.isucon9q.catatsuy.org` | `shipment.isucon9q.isuren.internal` | historical shipment name |
| `shipment.t.isucon.pw` / `bs.t.isucon.pw` | `shipment.t.isuren.internal` / `bs.t.isuren.internal` | maintained shipment names |

The self-signed test certificate covers the two Application names only. No TLS
or credential contract is claimed for the benchmark-owned mock names.

## Topology boundary

The official contest separated Web1 and Bench1. This recipe places the Go
Application, MySQL, nginx, benchmark binary, benchmark assets, and the
benchmark-owned payment/shipment mocks on one image for personal practice.
Only nginx is public. Payment and shipment bind to loopback during a benchmark
run; they are not persistent services.

The official benchmark node built its binary under
`/home/isucon/isucari/bin/benchmarker`. This recipe follows the established
KAKOMON13/14 practice-image layout instead: the final binary is
`/home/isuren/bench`, its authoritative-result wrapper is
`/home/isuren/run-benchmark`, and build-only `isucari/bench` source is removed.
The required runtime assets remain under `isucari/initial-data` and
`isucari/webapp/public/static`.

Run the benchmark as the practice user:

```bash
sudo -u isuren /home/isuren/run-benchmark
```

The wrapper preserves the official final JSON on stdout. Exit 0 means that
JSON had `pass=true`; `pass=false` becomes exit 2, missing/invalid final JSON
becomes exit 3, and a non-zero benchmark process status is preserved.

## Frontend exception

Frontend source is not managed and Node.js/npm are not installed. During the
AMI build, provisioning fetches the official prebuilt `webapp/public` Git tree
`a427d1c0adf7e8875d7dfbdca352de5a199edd69` byte-for-byte from the maintained
baseline. A generated `dist/` tree is optional local inspection output and is
not a Packer input.

The official service worker contains an unchanged Workbox 4.3.1 CDN import.
No bundled page registers that service worker. Artifact verification therefore
allows that one exact import, rejects any other occurrence of its CDN URL, and
rejects a registration call. It does not rebuild, delete, or rewrite the
official frontend.

The non-map bundle also contains documentation/error-help URLs (`reactjs.org`,
`redux.js.org`, `material-ui.com`, `fb.me`), and the images contain XML
namespace metadata. These are not endpoint dependencies. The preparation gate
separately rejects any embedded `catatsuy.org`, `isucon.pw`, or
`isuren.internal` competition/private domain; none exists in this tree.

## Responsibilities

1. `cloud-init/` checks out the exact isuren-mondai commit and calls
   `provisioning/all.sh`.
2. `provisioning/10-base.sh` installs the pinned build tools, then
   `05-artifacts.sh` fetches every official input at its exact commit/URL and
   verifies tree, manifest, and SHA-256 identities inside the AMI build.
3. `provisioning/` installs the runtime and services, consumes the verified
   inputs, installs the official public DB environment as
   `/home/isuren/env.sh`, records provenance, and runs Goss. The upstream MIT
   notice is also available as `/home/isuren/LICENSE`.
4. Packer waits for the completion marker and seals clone-local identity. It
   does not upload `dist/`; AMI build, fresh-boot, benchmark, Orb, and AWS
   product gates remain separate.

For optional local inspection, `mise run kakomon9-qualify:prepare-artifacts`
still writes an ignored `dist/` tree, but the normal Packer build does not need
or consume it.

The optional TLS certificate is generated during provisioning only when
`ENABLE_TEST_TLS=true`. It is a public practice fixture: its private key is
mode 0600, its SANs are `isucon9.isuren.internal` and
`isucari.t.isuren.internal`, and its fingerprint and usage warning are
recorded. It must never be used for mTLS, Portal authentication, credentials,
or trusted production traffic.
