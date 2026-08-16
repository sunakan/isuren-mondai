# Provisioning boundary

`all.sh` is the sole recipe entrypoint and executes every numbered step with
fail-fast status propagation. `10-base.sh` runs first so the AMI has the
required network/archive tools; `05-artifacts.sh` then fetches every pinned
official input inside the AMI and validates the complete artifact manifest
before any file is consumed. `50-source.sh` deploys the maintained Go source
and exact official data assets as real files. `80-frontend.sh` only places the
already verified official public tree; it never invokes Node.js, npm, a package
manager, minification, or domain replacement.

`99-verify.sh` downloads Goss 0.4.10 for linux-arm64 using a pinned URL and
SHA-256, performs image-state checks, then removes it. The durable evidence is
written under `/opt/isuren-mondai/kakomon9-qualify`.

The reset contract is `POST /initialize`. Service recovery is expressed only
as systemd `Restart=on-failure` and boot enablement. No contest restart command
or restart API is invented.
