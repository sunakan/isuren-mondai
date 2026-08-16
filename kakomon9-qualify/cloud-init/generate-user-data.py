#!/usr/bin/env python3
"""Generate small cloud-config that runs the exact recipe commit.

The large, ignored dist tree is uploaded by Packer. The embedded runner waits
for Packer's ready marker before invoking the same provisioning/all.sh used by
other environments.
"""

import base64
import os
import pathlib
import re


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
TEMPLATE = SCRIPT_DIR / "run-recipe.sh"
OUTPUT = SCRIPT_DIR / "user-data.yaml"


def main() -> None:
    commit = os.environ["PROJECT_COMMIT"]
    if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        raise SystemExit("PROJECT_COMMIT must be a full lowercase SHA")
    runner = TEMPLATE.read_text().replace("__PROJECT_COMMIT__", commit)
    encoded = base64.b64encode(runner.encode()).decode()
    content = "\n".join(
        [
            "#cloud-config",
            "write_files:",
            "  - path: /usr/local/sbin/kakomon9-qualify-provision",
            "    owner: root:root",
            "    permissions: '0755'",
            "    encoding: b64",
            f"    content: {encoded}",
            "runcmd:",
            "  - [/usr/local/sbin/kakomon9-qualify-provision]",
            "",
        ]
    )
    OUTPUT.write_text(content)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
