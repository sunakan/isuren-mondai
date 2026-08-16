#!/usr/bin/env python3
"""Add the Orb-only bootstrap to canonical kakomon cloud-config."""

import argparse
import pathlib

import yaml


CLOUD_CONFIG_HEADER = "#cloud-config\n"
ORB_BOOTSTRAP_MARKER = (
    "printf '%s\\n' '[orb-bootstrap] wait for IPv4 route and GitHub DNS'"
)
# Cloud-init emits string runcmd entries into one shell script. Keep set -eu first
# so a bootstrap or canonical recipe failure cannot be hidden by a later cleanup.
ORB_BOOTSTRAP_RUNCMD = [
    "set -eu",
    ORB_BOOTSTRAP_MARKER,
    "command -v ip >/dev/null",
    "command -v getent >/dev/null",
    "command -v apt-get >/dev/null",
    """orb_network_wait_seconds=120
while ! ip -4 route show default | grep -q . || ! getent ahostsv4 github.com >/dev/null 2>&1; do
  if [ "${orb_network_wait_seconds}" -eq 0 ]; then
    printf '%s\\n' '[orb-bootstrap] IPv4 route or GitHub DNS was not ready within 120 seconds' >&2
    exit 1
  fi
  sleep 1
  orb_network_wait_seconds=$((orb_network_wait_seconds - 1))
done""",
    "printf '%s\\n' '[orb-bootstrap] network is ready'",
    "printf '%s\\n' '[orb-bootstrap] install ca-certificates, git, and openssh-server'",
    "apt-get -o Acquire::Retries=5 update",
    (
        "DEBIAN_FRONTEND=noninteractive "
        "apt-get -o Acquire::Retries=5 -o DPkg::Lock::Timeout=120 "
        "install -y --no-install-recommends ca-certificates git openssh-server"
    ),
    "git --version",
    "test -x /usr/sbin/sshd",
    "systemctl cat ssh.service >/dev/null",
]


def load_cloud_config(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith(CLOUD_CONFIG_HEADER):
        raise ValueError(f"cloud-config header is missing: {path}")
    document = yaml.safe_load(text[len(CLOUD_CONFIG_HEADER) :])
    if not isinstance(document, dict):
        raise ValueError(f"cloud-config must be a mapping: {path}")
    return document


def prepare_cloud_config(document: dict) -> dict:
    runcmd = document.get("runcmd")
    if not isinstance(runcmd, list) or not runcmd:
        raise ValueError("cloud-config must contain a non-empty runcmd list")
    if ORB_BOOTSTRAP_MARKER in runcmd:
        raise ValueError("Orb bootstrap is already present")

    return {**document, "runcmd": [*ORB_BOOTSTRAP_RUNCMD, *runcmd]}


def write_cloud_config(path: pathlib.Path, document: dict) -> None:
    path.write_text(
        CLOUD_CONFIG_HEADER
        + yaml.safe_dump(document, allow_unicode=True, sort_keys=False, width=4096),
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()

    document = load_cloud_config(args.input)
    write_cloud_config(args.output, prepare_cloud_config(document))


if __name__ == "__main__":
    main()
