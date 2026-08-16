# KAKOMON13 provisioning contract

`all.sh` is the sole execution-order authority. It consumes committed managed
source, retrieves non-managed data from the exact official commit, and verifies
that data against `official-data.manifest.sha256`; `tmp/all-kakomon` is never
read by cloud-init or Packer.

The frontend is built outside the image with Node 24.19.0 and Yarn 3.2.2 and is
not tracked by Git. Provisioning requires an exact GitHub Release tag and
archive SHA-256, verifies the archive and its internal file manifest, copies
that manifest into the benchmark source, builds the benchmark with Go 1.26.6,
and only then installs the frontend and data into their final locations.

The common artifact intentionally contains no TLS private key, runtime address,
machine role, Portal credential, or `isu`. On a clone or fresh EC2 boot,
`kakomon13-instance-init.service` generates a new self-signed server key and
certificate for `pipe.u.isuren.internal`; this public practice certificate must
not be reused for mTLS, Portal authentication, or trusted traffic.

Goss validates the sealed single-host filesystem and service contract. It does
not establish Orb/AWS recipe, Golden, standalone, fresh-boot, or product Green.
