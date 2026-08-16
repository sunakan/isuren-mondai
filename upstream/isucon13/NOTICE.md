# isucon13 upstream NOTICE

- Official source: https://github.com/isucon/isucon13.git
- Baseline commit: `8f6afdc3603f0c661368de4659a7240862f59623`
- License: MIT (`LICENSE`; Copyright 2023 ISUCON13 Contributors)
- Local import source: the clean worktree-local mirror at
  `tmp/all-kakomon/isucon13`, copied from the verified main-checkout cache with
  `rsync -a` including its Git metadata.

## Managed source included here

- `webapp/go/**`: the Go Application only.
- `bench/**`: benchmark source, excluding its container definitions and binary
  image fixtures.
- `frontend/**`: frontend source and Yarn lock, excluding image assets and
  generated `node_modules` / `dist` trees.
- `webapp/pdns/u.isuren.internal.zone`: the official `webapp/pdns/u.isucon.dev.zone`
  full BIND zone file, renamed and with every `u.isucon.dev` occurrence
  rewritten to `u.isuren.internal`. This is the only source that provisions
  the full record set (well-known service names plus every official initial
  user) that the benchmarker's DNS pretest requires; the fresh-boot loader
  fills in `<ISUCON_SUBDOMAIN_ADDRESS>` and loads the zone with `pdnsutil
  load-zone`. `webapp/pdns/init_zone.sh` and `named.conf` are not imported:
  the former is superseded by the recipe's own fresh-boot script and the
  latter is an unused example left commented out in the official tree.

The import deliberately excludes other Application languages, official
provisioning, development containers, staff infrastructure, and generated
artifacts. This tree is maintained source derived from the baseline, not an
immutable mirror of the official repository.

## Local changes

- The Application cookie domain and PowerDNS zone calls, benchmark target / DNS
  zone, frontend Application hostname, and the imported
  `webapp/pdns/u.isuren.internal.zone` are changed only from `u.isucon.dev` to
  `u.isuren.internal`. The canonical target is `pipe.u.isuren.internal`.
- The recipe targets PowerDNS 5, which requires absolute owner names for
  `pdnsutil add-record`. Boot-time records and dynamically registered user
  records therefore use full names under `u.isuren.internal`; the official
  PowerDNS 4.8 environment accepted relative owner names.
- The Vite development server no longer reads the official, distributed TLS
  private key. Production TLS belongs to the recipe's fresh-boot initializer.
- Three pre-existing trailing spaces in `webapp/go/stats_handler.go` are
  removed so the repository whitespace gate remains clean; behavior is
  unchanged.
- `media.xiii.isucon.dev` is intentionally unchanged: it is an external media
  origin represented in official initial data and benchmark expectations, not
  a KAKOMON13 host provided by this recipe. The recipe's static contract lists
  and limits every permitted occurrence.

## Non-managed data and release boundary

The following baseline paths are not committed under `upstream/isucon13`:

- `frontend/src/assets/img/**`
- `frontend/src/components/layout/ISUPipe_yoko_color.png`
- `bench/internal/scheduler/images/**`
- `bench/scenario/testdata/NoImage.jpg`
- `webapp/img/NoImage.jpg`
- `webapp/sql/**`
- `scripts/initial-data/**`
- `development/pdns/20_powerdns_schema.sql`

No build output, release archive, image, or other binary is committed to this
repository. The two frontend paths are copied temporarily from the verified
worktree-local mirror for local builds, checked by
`kakomon13/scripts/frontend-assets.manifest.sha256`, and removed from managed
source after Vite writes `upstream/isucon13/frontend/dist/`. Release files are
assembled under ignored `kakomon13/dist/` and published separately with an
exact tag and SHA-256.

Cloud-init and AMI builds fetch the benchmark images, NoImage files, SQL, and
PowerDNS schema directly from the official URL at the exact baseline commit.
`kakomon13/provisioning/official-data.manifest.sha256` verifies every consumed
file before use. `scripts/initial-data/**` is classified as non-managed input
but is not consumed by this Go recipe because `webapp/sql/**` is the database
initialization authority. Clean clones do not depend on `tmp/` and do not use a
Git-managed data bundle.
