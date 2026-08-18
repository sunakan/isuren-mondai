# KAKOMON10-QUALIFY Packer input boundary

This directory only reserves the responsibility boundary for the AMI build.
Phase 1 of this session validated the recipe's components directly on an
aws-bastion EC2 instance (echo v5 migration, MySQL 8.4 schema/user, Node.js
14.9.0 frontend build, Faker initial-data generation, benchmark run) and
codified them as `../provisioning/*.sh`, but did not author or run a Packer
template. No `.pkr.hcl` exists here yet; do not treat this directory's
existence as `ami-build-green`.

When a future session adds the template, it must follow the same contract as
`kakomon12-qualify/packer` and `kakomon13/packer`:

- accept one exact `source_ami` value (Ubuntu 26.04 LTS arm64,
  `ap-northeast-1`); never perform AMI discovery (`most_recent` or otherwise)
- pin the Amazon plugin to an exact version
- wait for `provisioning/all.sh`'s completion marker
  (`/var/lib/cloud/kakomon10-qualify-provisioned`) and the Goss result before
  sealing
- tag the resulting AMI with the exact project commit, the resolved
  `kakomon10-qualify-frontend-*` Release tag, and its archive SHA-256
  (`/tmp/kakomon10-qualify-frontend-release-tag` /
  `/tmp/kakomon10-qualify-frontend-release-sha256`, written by
  `provisioning/60-initdb.sh`)
