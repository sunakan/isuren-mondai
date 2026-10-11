# KAKOMON10-QUALIFY Packer input boundary

`kakomon10-qualify.pkr.hcl` implements the ARM64 provider adapter and
`seal-image.sh` verifies the stopped image state after removing builder
identity. The recipe itself remains in `../provisioning/all.sh`; the
build host generates small User Data per exact commit and does not upload
local data/frontend artifacts. No Packer build or fresh AMI boot has been
run for this revision.

The build task `mise run kakomon10-qualify:build` loads the reviewed text
inputs from `../scripts/artifact-inputs.env` and follows this contract:

- use exact `source_ami=ami-0b39c0e7d24a8c3db` (Ubuntu 26.04 LTS arm64,
  `ap-northeast-1`, Canonical `099720109477`, image serial `20261003`);
  no AMI discovery or architecture fallback
- pin the Amazon plugin to `1.8.2`
- use `t4g.small` and an 8 GiB gp3 root with delete-on-termination;
  10q's peak/remaining disk usage is still a real-build validation gate
- resolve the existing Packer network stack Outputs with explicit Tokyo
  region, and associate a public address in its public subnet
- wait for `provisioning/all.sh`'s completion marker
  (`/var/lib/cloud/kakomon10-qualify-provisioned`) and the Goss result before
  sealing
- compare the downloaded Release tag/digest with the exact host inputs
  before seal; the verified archive contains frozen frontend/initial data
- tag AMI/snapshots with recipe and managed source trees, base image,
  architecture, official source, runtime/plugin, and frontend tag/digest
- preserve the permanent recipe-ready marker while cleaning cloud-init
  instance state so fresh CFn role User Data can run without rebuilding
- extract only the created artifact ID from the Packer manifest; retain
  the Packer failure status even when emitting host-side OTel spans

`packer validate -syntax-only` proves HCL syntax only. Plugin installation,
full plugin validation, AMI build, fresh boot, SSM, UUID/SSH regeneration,
and standalone benchmark/reset/recovery/reboot remain separate gates.
