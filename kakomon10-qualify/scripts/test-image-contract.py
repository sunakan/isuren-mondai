#!/usr/bin/env python3
"""Exercise fail-fast recipe bootstrap and CFn role/User Data contracts offline."""

import importlib.util
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "cloud_config", ROOT / "kakomon10-qualify/cloud-init/generate-user-data.py"
)
cloud_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cloud_config)
COMMIT = "a" * 40
TAG = "kakomon10-qualify-frontend-v1.0.0"
DIGEST = "b" * 64
AMI = "ami-0b39c0e7d24a8c3db"


class CloudInitTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.stage = pathlib.Path(self.temporary.name)
        original = (cloud_config.CLONE_DIR, cloud_config.PROVISIONING_DIR, cloud_config.READY_MARKER)
        self.addCleanup(self.restore_paths, original)
        cloud_config.CLONE_DIR = str(self.stage / "checkout")
        cloud_config.PROVISIONING_DIR = str(self.stage / "checkout/kakomon10-qualify/provisioning")
        cloud_config.READY_MARKER = str(self.stage / "recipe-ready")
        self.git_log = self.stage / "git.log"
        self.result = self.stage / "all-ran"
        (self.stage / "git").write_text(
            """#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$TEST_GIT_LOG"
case "$*" in
  *' fetch '*) exit "$TEST_FETCH_STATUS" ;;
  *' checkout '*)
    mkdir -p "$TEST_PROVISIONING_DIR"
    printf '#!/bin/bash\\nprintf ran > "$TEST_RESULT"\\nprintf "%%s\\n" "$RECIPE_COMMIT" > "$TEST_READY"\\n' > "$TEST_PROVISIONING_DIR/all.sh"
    ;;
esac
"""
        )
        (self.stage / "git").chmod(0o755)

    @staticmethod
    def restore_paths(original):
        cloud_config.CLONE_DIR, cloud_config.PROVISIONING_DIR, cloud_config.READY_MARKER = original

    def run_config(self, fetch_status=0):
        config = cloud_config.build_cloud_config(COMMIT, "", TAG, DIGEST, AMI)
        self.assertEqual(len(config["runcmd"]), 1)
        command = config["runcmd"][0]
        subprocess.run(["bash", "-n", "-c", command[2]], check=True)
        return subprocess.run(
            command,
            env={
                **os.environ,
                "PATH": str(self.stage) + os.pathsep + os.environ["PATH"],
                "TEST_GIT_LOG": str(self.git_log),
                "TEST_FETCH_STATUS": str(fetch_status),
                "TEST_PROVISIONING_DIR": cloud_config.PROVISIONING_DIR,
                "TEST_RESULT": str(self.result),
                "TEST_READY": cloud_config.READY_MARKER,
            },
            capture_output=True,
            text=True,
        )

    def test_fetch_failure_never_runs_checkout_or_recipe(self):
        result = self.run_config(fetch_status=23)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertNotIn(" checkout ", self.git_log.read_text())
        self.assertFalse(self.result.exists())
        self.assertFalse(pathlib.Path(cloud_config.READY_MARKER).exists())

    def test_success_runs_recipe_and_removes_temporary_checkout(self):
        result = self.run_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.result.read_text(), "ran")
        self.assertEqual(pathlib.Path(cloud_config.READY_MARKER).read_text().strip(), COMMIT)
        self.assertFalse(pathlib.Path(cloud_config.CLONE_DIR).exists())

    def test_sealed_ready_marker_skips_all_network_and_provisioning(self):
        pathlib.Path(cloud_config.READY_MARKER).write_text(COMMIT + "\n")
        result = self.run_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.git_log.exists())
        self.assertFalse(self.result.exists())

    def test_ready_marker_for_another_recipe_fails_without_network(self):
        pathlib.Path(cloud_config.READY_MARKER).write_text("c" * 40 + "\n")
        result = self.run_config()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.git_log.exists())

    def test_rejects_injection_wrong_target_and_mutable_packer_input(self):
        for args in (
            (COMMIT + ";true", "", TAG, DIGEST, AMI),
            (COMMIT, "bad", TAG, DIGEST, AMI),
            (COMMIT, "", "kakomon14-frontend-v1.0.0", DIGEST, AMI),
            (COMMIT, "", TAG, DIGEST + ";true", AMI),
            (COMMIT, "", "latest", DIGEST, AMI),
            (COMMIT, "", TAG, "", AMI),
        ):
            with self.subTest(args=args), self.assertRaises(ValueError):
                cloud_config.build_cloud_config(*args)


class CfnLoader(yaml.SafeLoader):
    pass


def load_tag(loader, tag, node):
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node)
    else:
        value = loader.construct_mapping(node)
    return {tag: value}


CfnLoader.add_multi_constructor("!", load_tag)


class CfnRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = yaml.load(
            (ROOT / "cfn/kakomon10-qualify-1bench-1web.yaml").read_text(), Loader=CfnLoader
        )

    def test_arm64_roles_and_public_http_match_the_recipe(self):
        resources = self.template["Resources"]
        instances = [item for item in resources.values() if item["Type"] == "AWS::EC2::Instance"]
        self.assertEqual(len(instances), 2)
        for item in instances:
            self.assertEqual(item["Properties"]["InstanceType"], "c8g.large")
            self.assertEqual(item["Properties"]["ImageId"], {"Ref": "AmiId"})
            self.assertTrue(item["Properties"]["BlockDeviceMappings"][0]["Ebs"]["DeleteOnTermination"])
        web_ports = {
            rule["FromPort"]
            for rule in resources["WebSecurityGroup"]["Properties"]["SecurityGroupIngress"]
            if rule.get("CidrIp") == "0.0.0.0/0"
        }
        self.assertEqual(web_ports, {22, 80})

    def test_cfn_substitution_preserves_shell_variables_and_role_checks(self):
        def substitute(match):
            name = match.group(1)
            if name.startswith("!"):
                return "${" + name[1:] + "}"
            return {"AWS::Region": "ap-northeast-1", "GithubUsers": "example-user"}[name]

        resources = self.template["Resources"]
        for name, state in (("Web1Instance", "web"), ("BenchInstance", "bench")):
            user_data = resources[name]["Properties"]["UserData"]["Fn::Base64"]["Sub"]
            rendered = re.sub(r"\$\{([^}]+)\}", substitute, user_data)
            subprocess.run(["bash", "-n", "-c", rendered], check=True)
            self.assertIn('"https://github.com/${u}.keys"', rendered)
            self.assertIn(f"kakomon10-qualify-check-image-state {state}", rendered)
            if state == "bench":
                self.assertIn("for svc in isuumo-go nginx mysql", rendered)
                self.assertLess(rendered.index("systemctl disable --now"), rendered.index("check-image-state bench"))

    def test_provisioning_goss_observes_without_resetting_data(self):
        spec = yaml.safe_load((ROOT / "kakomon10-qualify/provisioning/goss.yaml").read_text())
        for command in spec["command"].values():
            self.assertNotIn("/initialize", command["exec"])
            self.assertNotIn("systemctl start", command["exec"])


if __name__ == "__main__":
    unittest.main()
