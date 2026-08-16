# KAKOMON13 Packer input boundary

The build accepts one exact `source_ami` value and never performs AMI discovery.
The caller must resolve and review an Ubuntu 26.04 arm64 Canonical image ID in
the external-operation preflight. No default, `most_recent`, older OS, or amd64
fallback exists.

The Amazon plugin is fixed to 1.8.2. The AMI tags bind the exact project commit,
KAKOMON13 tree, official source commit and data-manifest digest, input AMI ID,
exact frontend Release tag and archive SHA-256, OS, and architecture. The
frontend Release and official binary/data files are external inputs; none are
stored in this Git repository.
