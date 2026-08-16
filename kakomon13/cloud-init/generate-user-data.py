#!/usr/bin/env python3
"""Generate cloud-config for one exact isuren-mondai recipe commit."""

import argparse
import os
import pathlib
import re

import yaml

REPO_URL = "https://github.com/sunakan/isuren-mondai.git"
CLONE_DIR = "/opt/isuren-mondai"
PROVISIONING_DIR = f"{CLONE_DIR}/kakomon13/provisioning"


def build_cloud_config(
    commit: str, traceparent: str, frontend_release_tag: str, frontend_release_sha256: str
) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("PROJECT_COMMIT must be a full lowercase Git SHA")
    if traceparent and not re.fullmatch(r"00-[0-9a-f]{32}-[0-9a-f]{16}-01", traceparent):
        raise ValueError("TRACEPARENT has an invalid format")
    if not re.fullmatch(r"kakomon13-frontend-v[0-9]+\.[0-9]+\.[0-9]+", frontend_release_tag):
        raise ValueError("FRONTEND_RELEASE_TAG must be one exact semantic-version tag")
    if not re.fullmatch(r"[0-9a-f]{64}", frontend_release_sha256):
        raise ValueError("FRONTEND_RELEASE_SHA256 must be one exact lowercase SHA-256")
    return {
        "runcmd": [
            f"git init --quiet {CLONE_DIR}",
            f"git -C {CLONE_DIR} remote add origin {REPO_URL}",
            f"git -C {CLONE_DIR} fetch --quiet --depth 1 origin {commit}",
            f"git -C {CLONE_DIR} checkout --quiet {commit}",
            (
                f"env RECIPE_COMMIT={commit} TRACEPARENT={traceparent} "
                f"FRONTEND_RELEASE_TAG={frontend_release_tag} "
                f"FRONTEND_RELEASE_SHA256={frontend_release_sha256} "
                f"bash {PROVISIONING_DIR}/all.sh"
            ),
            f"rm -rf {CLONE_DIR}",
        ]
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    config = build_cloud_config(
        os.environ["PROJECT_COMMIT"],
        os.environ.get("TRACEPARENT", ""),
        os.environ["FRONTEND_RELEASE_TAG"],
        os.environ["FRONTEND_RELEASE_SHA256"],
    )
    args.output.write_text(
        "#cloud-config\n" + yaml.safe_dump(config, allow_unicode=True, sort_keys=False, width=4096)
    )
    print(args.output)


if __name__ == "__main__":
    main()
