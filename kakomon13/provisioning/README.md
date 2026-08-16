# KAKOMON13 provisioning contract

`all.sh` is the sole execution-order authority. It consumes committed managed
source, retrieves non-managed data from the exact official commit, and verifies
that data against `official-data.manifest.sha256`; `tmp/all-kakomon` is never
read by cloud-init or Packer.

The frontend is built outside the image with Node 24.19.0 and Yarn 3.2.2 and is
not tracked by Git. Provisioning resolves the target-scoped `latest` selector
to a `kakomon13-frontend-*` GitHub Release, verifies the archive with its
published outer SHA-256 asset and internal file manifest, copies that manifest
into the benchmark source, builds the benchmark with Go 1.26.6, and only then
installs the frontend and data into their final locations. The resolved tag and
archive digest are persisted for provenance and the AMI build host.
Go is installed and invoked through the same home-owned mise layout as
KAKOMON14; `/opt/go-*` and `/usr/local/bin/go` are not part of this recipe.
The mise v2026.8.6 Linux arm64 binary is fetched on the image builder from its
exact release URL and checked against its published SHA-256 before install.

Where the official recipe writes `/home/isucon`, this recipe preserves the
same relative layout below `/home/isuren`. In particular, systemd reads
`/home/isuren/env.sh`. The file contains the official environment keys and is
rendered on each clone or fresh boot so the PowerDNS address belongs to that
machine. It is therefore absent only from the sealed common artifact.

The common artifact intentionally contains no TLS private key, runtime address,
machine role, Portal credential, or `isu`. On a clone or fresh EC2 boot,
`kakomon13-instance-init.service` waits for the IPv4 default route and its
global address, then generates a new self-signed server key and certificate for
`pipe.u.isuren.internal`; this public practice certificate must not be reused
for mTLS, Portal authentication, or trusted traffic.

Goss validates the sealed single-host filesystem and service contract. It does
not establish Orb/AWS recipe, Golden, standalone, fresh-boot, or product Green.
