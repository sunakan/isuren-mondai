#!/usr/bin/env python3
"""Exercise Release repair, real assembly, and publication guards without APIs."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

import yaml

from benchmark_data import check_benchmark_data, SNAPSHOT_DIRECTORIES
from repair_frontend_release import digest, manifest_files, repair_archive, verify_manifest

ROOT = Path(__file__).resolve().parents[2]
BASE_TAG = "kakomon10-qualify-frontend-v1.0.0"
NEW_TAG = "kakomon10-qualify-frontend-v1.0.1"


class BenchmarkDataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.stage = Path(self.temporary.name)
        self.release = self.stage / "release"
        self.result = self.release / "initial-data-result"
        self.fixture = self.release / "fixture"
        for kind in ("chair", "estate"):
            self.write_records(self.result / f"{kind}_json.txt", range(1, 29501))
            self.write_records(self.result / f"verify_draft_{kind}.txt", range(29501, 30001))
            for index in range(20):
                first = 30001 + index * 500
                self.write_records(self.result / "draft_data" / kind / f"{index}.txt", range(first, first + 500))
            self.write(self.fixture / f"{kind}_condition.json", '{"fixture":true}')
        for name in SNAPSHOT_DIRECTORIES:
            self.write(self.result / "verification_data" / name / "0.json", '{"request":{},"response":{}}')
        self.write(self.release / "mysql/1_DummyEstateData.sql", "frozen estate SQL\n")
        self.write(self.release / "mysql/2_DummyChairData.sql", "frozen chair SQL\n")
        self.write(self.release / "public/index.html", "frozen frontend\n")
        self.write(self.release / "public/images/fixture.png", "frozen image bytes\n")
        self.write(self.release / "LICENSE", "fixture license\n")
        self.generated = self.stage / "generated"
        shutil.copytree(self.result, self.generated)
        for name in ("1_DummyEstateData.sql", "2_DummyChairData.sql"):
            shutil.copyfile(self.release / "mysql" / name, self.generated / name)
        for name in ("chair_condition.json", "estate_condition.json"):
            shutil.copyfile(self.fixture / name, self.generated / name)
        for kind in ("chair", "estate"):
            (self.result / f"verify_draft_{kind}.txt").unlink()
        self.write(self.release / "MANIFEST.sha256", "".join(
            f"{digest(path)}  {path.relative_to(self.release)}\n" for path in manifest_files(self.release)
        ))
        self.frozen = verify_manifest(self.release)
        self.base_archive = self.stage / "base.tar.gz"
        with tarfile.open(self.base_archive, "w:gz") as archive:
            archive.add(self.release, arcname=".")
        self.base_sha = digest(self.base_archive)
        self.output = self.stage / "repaired.tar.gz"

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    @classmethod
    def write_records(cls, path, ids):
        cls.write(path, "".join(json.dumps({"id":identifier,"stock":1}) + "\n" for identifier in ids))

    def repair(self):
        repair_archive(self.base_archive, self.base_sha, BASE_TAG, self.generated, self.output)

    def test_complete_inputs_pass_and_old_release_is_rejected(self):
        check_benchmark_data(self.generated, self.fixture)
        with self.assertRaisesRegex(ValueError, "verify_draft"):
            check_benchmark_data(self.result, self.fixture)

    def test_missing_read_paths_and_invalid_stock_are_rejected(self):
        paths = [self.generated / "verify_draft_chair.txt", self.generated / "verify_draft_estate.txt",
                 self.generated / "draft_data/chair/0.txt", self.fixture / "estate_condition.json",
                 self.generated / "verification_data/estate_nazotte/0.json"]
        for path in paths:
            with self.subTest(path=path):
                saved = path.read_text()
                path.unlink()
                try:
                    with self.assertRaises(ValueError):
                        check_benchmark_data(self.generated, self.fixture)
                finally:
                    self.write(path, saved)
        path = self.generated / "verify_draft_chair.txt"
        path.write_text(path.read_text().replace('"stock": 1', '"stock": 2', 1))
        with self.assertRaisesRegex(ValueError, "stock=1"):
            check_benchmark_data(self.generated, self.fixture)

    def test_repair_adds_two_inputs_and_preserves_every_frozen_byte(self):
        self.repair()
        unpacked = self.stage / "unpacked"
        with tarfile.open(self.output) as archive:
            archive.extractall(unpacked, filter="data")
        final = verify_manifest(unpacked)
        for name, sha in self.frozen.items():
            self.assertEqual(final[name], sha, name)
        added = set(final) - set(self.frozen)
        self.assertEqual(added, {"initial-data-result/verify_draft_chair.txt",
                                 "initial-data-result/verify_draft_estate.txt", "BENCHMARK-REPAIR.txt"})
        check_benchmark_data(unpacked / "initial-data-result", unpacked / "fixture")
        self.assertEqual(digest(self.base_archive), self.base_sha)
        self.assertIn(digest(self.output), Path(str(self.output) + ".sha256").read_text())

    def test_regenerated_sql_json_fixture_or_draft_difference_rejects_repair(self):
        for name in ("1_DummyEstateData.sql", "chair_json.txt", "chair_condition.json", "draft_data/estate/0.txt"):
            with self.subTest(name=name):
                path = self.generated / name
                saved = path.read_text()
                path.write_text(saved + "different\n")
                try:
                    with self.assertRaisesRegex(ValueError, "differs from the frozen"):
                        self.repair()
                    self.assertFalse(self.output.exists())
                finally:
                    path.write_text(saved)

    def test_existing_metadata_cannot_be_overwritten_during_repair(self):
        self.write(self.release / "BENCHMARK-REPAIR.txt", "existing frozen metadata\n")
        self.write(self.release / "MANIFEST.sha256", "".join(
            f"{digest(path)}  {path.relative_to(self.release)}\n" for path in manifest_files(self.release)
        ))
        with tarfile.open(self.base_archive, "w:gz") as archive:
            archive.add(self.release, arcname=".")
        self.base_sha = digest(self.base_archive)
        with self.assertRaisesRegex(ValueError, "preserved Release file changed"):
            self.repair()
        self.assertFalse(self.output.exists())

    def test_wrong_base_checksum_rejects_repair(self):
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            repair_archive(self.base_archive, "0" * 64, BASE_TAG, self.generated, self.output)
        self.assertFalse(self.output.exists())

    def test_real_normal_assembly_copies_the_complete_benchmark_tree(self):
        stage_root = self.stage / "generation"
        shutil.copytree(self.generated, stage_root / "initial-data/result")
        for source, target in ((self.fixture, "webapp/fixture"), (self.release / "public", "webapp/frontend/out")):
            shutil.copytree(source, stage_root / target)
        script = (ROOT / "kakomon10-qualify/scripts/build-frontend-release.sh").read_text()
        assembly = script[script.index('install -d -m 0755 "${RELEASE_DIST}"', script.index('# 5. Assemble')):
                          script.index('(\n  cd "${release}"', script.index('# 5. Assemble'))]
        environment = {**os.environ, "ROOT_DIR": str(ROOT), "RELEASE_DIST": str(self.stage / "dist"),
                       "MANAGED": str(self.release), "stage_root": str(stage_root), "work": str(self.stage / "assembled")}
        completed = subprocess.run(["bash", "-eu", "-c", assembly], env=environment, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        assembled = self.stage / "assembled/release"
        check_benchmark_data(assembled / "initial-data-result", assembled / "fixture")


class PublicationGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.commands = self.root / "commands"
        self.commands.mkdir()
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/lib.sh", self.root / "scripts/lib.sh")
        (self.root / "kakomon10-qualify/scripts").mkdir(parents=True)
        self.write_script(self.root / "kakomon10-qualify/scripts/build-frontend-release.sh",
                          'test -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}"\nprintf build >> "$TEST_LOG"\n')
        self.write_script(self.root / "scripts/github-release.sh", 'test -n "${GH_TOKEN:-}"\nprintf upload >> "$TEST_LOG"\n')
        self.write_script(self.commands / "git", '''case "$1" in
status) exit 0 ;;
rev-parse) printf '%040d\\n' 0 ;;
ls-remote) printf '%s' "$REMOTE_TAG"; exit "$REMOTE_STATUS" ;;
*) exit 99 ;;
esac
''')
        self.write_script(self.commands / "gh", '''case "$1 $2" in
"api "*) exit 0 ;;
"release list") printf '%s' "$PUBLISHED_TAGS"; exit "$GH_STATUS" ;;
*) exit 99 ;;
esac
''')
        self.write_script(self.commands / "mise", 'test -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}"\nprintf build >> "$TEST_LOG"\n')
        self.log = self.root / "operation.log"

    @staticmethod
    def write_script(path, text):
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + text)
        path.chmod(0o755)

    def run_task(self, task="repair-frontend", tag=NEW_TAG, **overrides):
        environment = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                       "GH_TOKEN":"fixture-token", "GITHUB_TOKEN":"fixture-token", "TEST_LOG":str(self.log),
                       "REMOTE_TAG":"", "REMOTE_STATUS":"0", "PUBLISHED_TAGS":"[]", "GH_STATUS":"0", **overrides}
        arguments = [tag, BASE_TAG, "b" * 64] if task == "repair-frontend" else [tag]
        return subprocess.run(["bash", str(ROOT / "mise-tasks/kakomon10-qualify" / task), *arguments],
                              cwd=self.root, env=environment, capture_output=True, text=True)

    def test_same_base_tag_existing_tag_and_existing_release_stop_before_build(self):
        for arguments in ({"tag":BASE_TAG}, {"REMOTE_TAG":"existing tag"},
                          {"PUBLISHED_TAGS":json.dumps([{"tagName":NEW_TAG}])}):
            with self.subTest(arguments=arguments):
                result = self.run_task(**arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists())

    def test_remote_read_failure_and_invalid_json_stop_before_build(self):
        for arguments in ({"REMOTE_STATUS":"31"}, {"GH_STATUS":"32"}, {"PUBLISHED_TAGS":"invalid"}):
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_task(**arguments).returncode, 0)
                self.assertFalse(self.log.exists())

    def test_success_isolates_tokens_from_build_and_preserves_upload_token(self):
        result = self.run_task()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), "buildupload")

    def test_normal_push_also_rejects_an_existing_release_before_build(self):
        result = self.run_task(task="release", PUBLISHED_TAGS=json.dumps([{"tagName":NEW_TAG}]))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())


class WorkflowContractTests(unittest.TestCase):
    def test_dispatch_and_push_share_destination_tag_guard_and_separate_build_modes(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/release-kakomon10-qualify-frontend.yml").read_text())
        events = workflow.get("on", workflow.get(True))
        self.assertEqual(events["push"]["tags"], ["kakomon10-qualify-frontend-v*"])
        self.assertEqual(set(events["workflow_dispatch"]["inputs"]), {"release_tag", "base_tag", "base_sha256"})
        self.assertIn("inputs.release_tag || github.ref_name", workflow["concurrency"]["group"])
        steps = workflow["jobs"]["release"]["steps"]
        full = next(step for step in steps if "mise run kakomon10-qualify:release" in step.get("run", ""))
        repair = next(step for step in steps if "repair-frontend" in step.get("run", ""))
        self.assertEqual(full["if"], "github.event_name == 'push'")
        self.assertEqual(repair["if"], "github.event_name == 'workflow_dispatch'")
        self.assertIn('"$REPAIR_TAG" "$BASE_TAG" "$BASE_SHA256"', repair["run"])


if __name__ == "__main__":
    unittest.main()
