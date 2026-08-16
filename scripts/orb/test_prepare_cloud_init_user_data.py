#!/usr/bin/env python3
"""Tests for the Orb-only cloud-config bootstrap."""

import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("prepare-cloud-init-user-data.py")
SPEC = importlib.util.spec_from_file_location("prepare_cloud_init_user_data", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PrepareCloudConfigTest(unittest.TestCase):
    def test_prepends_bootstrap_and_preserves_canonical_commands(self) -> None:
        original_runcmd = ["git init /opt/example", "bash /opt/example/all.sh"]
        document = {"packages": ["curl"], "runcmd": original_runcmd}

        prepared = MODULE.prepare_cloud_config(document)

        self.assertEqual(prepared["packages"], ["curl"])
        self.assertEqual(
            prepared["runcmd"][: len(MODULE.ORB_BOOTSTRAP_RUNCMD)],
            MODULE.ORB_BOOTSTRAP_RUNCMD,
        )
        self.assertEqual(
            prepared["runcmd"][len(MODULE.ORB_BOOTSTRAP_RUNCMD) :],
            original_runcmd,
        )
        self.assertEqual(document["runcmd"], original_runcmd)

    def test_installs_and_verifies_openssh_server(self) -> None:
        commands = MODULE.ORB_BOOTSTRAP_RUNCMD

        self.assertTrue(
            any(
                "install -y --no-install-recommends ca-certificates git openssh-server"
                in command
                for command in commands
            )
        )
        self.assertIn("test -x /usr/sbin/sshd", commands)
        self.assertIn("systemctl cat ssh.service >/dev/null", commands)

    def test_rejects_missing_runcmd(self) -> None:
        with self.assertRaisesRegex(ValueError, "non-empty runcmd"):
            MODULE.prepare_cloud_config({})

    def test_rejects_duplicate_bootstrap(self) -> None:
        document = {
            "runcmd": [*MODULE.ORB_BOOTSTRAP_RUNCMD, "git init /opt/example"],
        }

        with self.assertRaisesRegex(ValueError, "already present"):
            MODULE.prepare_cloud_config(document)


if __name__ == "__main__":
    unittest.main()
