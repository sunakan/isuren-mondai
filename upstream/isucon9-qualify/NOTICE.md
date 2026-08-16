# isucon9-qualify managed source NOTICE

- Official repository: https://github.com/isucon/isucon9-qualify
- Historical original commit: `34b3e785ebdd97d5c39a1263cbf56d1ae5e3ef91`
- Managed baseline commit: `ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0`
- License: MIT (`LICENSE`; Copyright 2019 ISUCON9 Contributors)

This directory is the Go Application and benchmark source maintained by
isuren-mondai. It is not a byte-for-byte mirror of either official revision.
The local audit checkout under `tmp/all-kakomon/` is evidence only and is not a
build input.

## Original-to-maintained baseline

The maintained baseline modernizes both Go modules and their dependencies,
updates the HTTP stack, removes the pre-Go-1.13 benchmark implementation,
updates deprecated random APIs, and changes the shipment mock from port 7000
to port 7001. The AMI recipe builds this baseline with Go 1.26.6; it does not
fall back to the historical Go versions.

## Managed paths

- `go.mod`, `go.sum`
- `cmd/bench/main.go`
- `bench/asset`, `bench/fails`, `bench/scenario`, `bench/server`, `bench/session`
- `webapp/go` except its container-only Dockerfile and `.gitignore`

The organizer Portal benchmark worker, development-only standalone
payment/shipment commands, other language implementations, Ansible roles, and
container build files are outside this recipe.

## Local maintenance changes

- `cmd/bench/main.go`: default benchmark host is
  `isucon9.isuren.internal`, preserving the official application subdomain
  while moving it under the adopted private domain.
- `cmd/bench/main.go`: default benchmark URL uses nginx at
  `http://isucon9.isuren.internal`; the Application remains loopback-only at
  `127.0.0.1:8000`.
- `webapp/go/main.go`: propagate `../init.sh` execution failure from
  `POST /initialize` instead of checking a stale error value.
- `webapp/go/main.go`: bind the Application to `127.0.0.1:8000`; nginx is
  the only public entry point in this recipe.

Updates must name both the old and new full official commit IDs and show the
managed-tree diff before replacement. They are never taken automatically from
`master`, another floating ref, or the audit checkout's current HEAD.

## Source and assets intentionally not managed here

Frontend source is not managed or built by isuren-mondai. The official
prebuilt `webapp/public` tree is copied byte-for-byte from commit
`ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0`; its Git tree is
`a427d1c0adf7e8875d7dfbdca352de5a199edd69`.

The tree's `service-worker.js` retains its exact Workbox 4.3.1 CDN import at
`https://storage.googleapis.com/workbox-cdn/releases/4.3.1/workbox-sw.js`.
No shipped page or bundle registers that service worker. The target accepts
this one dormant official reference, monitors both facts during artifact
preparation and provisioning, and does not delete or rewrite it.

The following unmodified inputs are fetched during the AMI build by
`kakomon9-qualify/provisioning/05-artifacts.sh` and are not committed as
managed source. The optional local
`kakomon9-qualify/scripts/prepare-artifacts.sh` task is only for inspection;
Packer does not upload its `dist/` output:

- `webapp/public/**` from the managed baseline commit
- `webapp/init.sh` and `webapp/sql/{00_create_database.sql,01_schema.sql,02_categories.sql}`
  from the managed baseline commit
- benchmark support files `initial-data/{image_files_md5_json.txt,keywords.tsv}`
  and `initial-data/result/category_json.txt` from the managed baseline commit
- release `v2` assets `initial.zip`, `bench1.zip`, and `initial-data.zip`

The target-specific AMI provisioning pins and verifies the URLs, Git commit,
Git tree, file manifests, and SHA-256 values before any service consumes them.
