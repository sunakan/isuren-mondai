#!/usr/bin/env python3
"""Generate cloud-config for one exact isuren-mondai recipe commit."""

import argparse
import os
import pathlib
import re

import yaml


REPO_URL = "https://github.com/sunakan/isuren-mondai.git"
CLONE_DIR = "/opt/isuren-mondai-source"
PROVISIONING_DIR = f"{CLONE_DIR}/kakomon10-qualify/provisioning"
READY_MARKER = "/var/lib/isuren-mondai/kakomon10-qualify/recipe-ready"


def build_cloud_config(
    commit: str,
    traceparent: str,
    frontend_tag: str = "latest",
    frontend_sha256: str = "",
    source_ami: str = "not-applicable",
) -> dict:
    if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        raise ValueError("PROJECT_COMMIT must be a full lowercase Git SHA")
    if traceparent and re.fullmatch(r"00-[0-9a-f]{32}-[0-9a-f]{16}-01", traceparent) is None:
        raise ValueError("TRACEPARENT has an invalid format")
    if frontend_tag != "latest" and re.fullmatch(
        r"kakomon10-qualify-frontend-v[0-9]+\.[0-9]+\.[0-9]+", frontend_tag
    ) is None:
        raise ValueError("FRONTEND_RELEASE_TAG has an invalid target prefix")
    if frontend_sha256 and re.fullmatch(r"[0-9a-f]{64}", frontend_sha256) is None:
        raise ValueError("FRONTEND_RELEASE_SHA256 must be lowercase SHA-256")
    if source_ami != "not-applicable" and re.fullmatch(r"ami-[0-9a-f]{17}", source_ami) is None:
        raise ValueError("SOURCE_AMI_ID must be an exact AMI ID")
    if source_ami != "not-applicable" and (frontend_tag == "latest" or not frontend_sha256):
        raise ValueError("Packer requires a resolved frontend tag and SHA-256")
    # 一つのshellでfail-fastにし、取得失敗後に古いtreeを実行しない。
    script = f"""set -euo pipefail
if [ -f {READY_MARKER} ]; then
  test \"$(cat {READY_MARKER})\" = {commit}
  exit 0
fi
test ! -e {CLONE_DIR}
git init --quiet {CLONE_DIR}
git -C {CLONE_DIR} remote add origin {REPO_URL}
git -C {CLONE_DIR} fetch --quiet --depth 1 origin {commit}
git -C {CLONE_DIR} checkout --quiet {commit}
env PROJECT_ROOT={CLONE_DIR} RECIPE_COMMIT={commit} TRACEPARENT={traceparent} \\
  FRONTEND_RELEASE_TAG={frontend_tag} FRONTEND_RELEASE_SHA256={frontend_sha256} \\
  SOURCE_AMI_ID={source_ami} bash {PROVISIONING_DIR}/all.sh
rm -rf {CLONE_DIR}
"""
    return {
        "packages": ["git"],
        "runcmd": [["bash", "-c", script]],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    inputs_path = pathlib.Path(__file__).resolve().parents[1] / "scripts/artifact-inputs.env"
    inputs = dict(
        line.split("=", 1)
        for line in inputs_path.read_text().splitlines()
        if line and not line.startswith("#")
    )
    config = build_cloud_config(
        os.environ["PROJECT_COMMIT"],
        os.environ.get("TRACEPARENT", ""),
        os.environ.get("FRONTEND_RELEASE_TAG", inputs["KAKOMON10_QUALIFY_FRONTEND_RELEASE_TAG"]),
        os.environ.get("FRONTEND_RELEASE_SHA256", inputs["KAKOMON10_QUALIFY_FRONTEND_RELEASE_SHA256"]),
        os.environ.get("SOURCE_AMI_ID", "not-applicable"),
    )
    args.output.write_text(
        "#cloud-config\n" + yaml.safe_dump(config, allow_unicode=True, sort_keys=False, width=4096)
    )
    print(args.output)


if __name__ == "__main__":
    main()
