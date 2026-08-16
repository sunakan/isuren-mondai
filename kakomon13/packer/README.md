# KAKOMON13 Packer input boundary

The Packer template accepts one exact `source_ami` value and never performs AMI
discovery. The normal `mise kakomon13:build` task loads the reviewed value from
`kakomon13/scripts/ami-inputs.env`; direct Packer invocations still need to pass
the value explicitly. No `most_recent`, older OS, or amd64 fallback exists.

The Amazon plugin is fixed to 1.8.2. The AMI tags bind the exact project commit,
KAKOMON13 tree, official source commit and data-manifest digest, input AMI ID,
exact frontend Release tag and archive SHA-256, OS, and architecture. The
frontend Release and official binary/data files are external inputs; none are
stored in this Git repository.
