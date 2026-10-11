#!/usr/bin/env python3
"""実AWSを呼ばず、AMI taskの確認と破壊境界を検証する。"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ACCOUNT = "111122223333"
PREFIX = "isuren/kakomon10-qualify-arm64-"


def image(number, **updates):
    row = {
        "ImageId": f"ami-{number:017x}", "OwnerId": ACCOUNT,
        "Name": PREFIX + str(number), "Architecture": "arm64", "State": "available",
        "CreationDate": f"2026-08-{number:02d}T00:00:00.000Z", "Public": False,
        "RootDeviceType": "ebs", "BlockDeviceMappings": [{"DeviceName": "/dev/sda1",
            "Ebs": {"SnapshotId": f"snap-{number:017x}", "Encrypted": False, "VolumeSize": 8}}],
    }
    row.update(updates)
    return row


def aws_stub():
    state_path = Path(os.environ["KAKOMON10_AMI_TASK_STUB_STATE"])
    state = json.loads(state_path.read_text())
    args = sys.argv[2:]
    assert args[args.index("--region") + 1] == "ap-northeast-1"
    assert args[args.index("--output") + 1] == "json"
    assert "--no-cli-pager" in args and "--no-cli-auto-prompt" in args
    service, operation = args[:2]
    assert (service, operation) in {
        ("sts", "get-caller-identity"), ("ec2", "describe-images"),
        ("ec2", "describe-snapshots"), ("ec2", "modify-image-attribute"),
        ("ec2", "deregister-image"), ("ec2", "delete-snapshot"),
    }, args
    state["calls"].append(args)
    state["counts"][operation] = state["counts"].get(operation, 0) + 1
    count = state["counts"][operation]
    output, code = None, 0
    option = lambda flag: args[args.index(flag) + 1]
    if state.get("fail") == [operation, count]:
        code = 23
    elif operation == "get-caller-identity":
        output = {"Account": ACCOUNT}
    elif operation == "describe-images":
        assert "--include-deprecated" in args and "--include-disabled" in args
        if "--image-ids" in args and any(flag in args for flag in ("--page-size", "--max-results")):
            state_path.write_text(json.dumps(state))
            print("An error occurred (InvalidParameterCombination) when calling the DescribeImages operation: "
                  "imageIdsSet cannot be used with maxResults", file=sys.stderr)
            return 254
        assert "--no-paginate" not in args and "--max-items" not in args and "--query" not in args
        if "--image-ids" in args:
            ami_id = option("--image-ids")
            assert option("--owners") == "self"
            rows = [i for i in state["images"] if i["ImageId"] == ami_id]
            if state.get("changed_target") and ami_id == image(1)["ImageId"]:
                rows = copy.deepcopy(rows)
                rows[0]["Name"] += "-changed"
        elif "block-device-mapping.snapshot-id" in " ".join(args):
            assert "--owners" not in args
            snapshot = option("--filters").split("Values=", 1)[1]
            state["reference_count"] += 1
            if state.get("reference_fail") == state["reference_count"]:
                code = 24
            if state.get("new_reference") and state["reference_count"] > 2:
                new = image(8, OwnerId="999900001111", Architecture="x86_64", State="disabled")
                new["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"] = snapshot
                state["images"].append(new)
            rows = [i for i in state["images"] if any(
                m.get("Ebs", {}).get("SnapshotId") == snapshot for m in i["BlockDeviceMappings"])]
        else:
            assert option("--owners") == "self"
            assert "Name=name,Values=" + PREFIX + "*" in args
            assert "Name=state,Values=available" in args and "Name=architecture,Values=arm64" in args
            state["list_count"] += 1
            if state.get("changed_list") and state["list_count"] == 2:
                state["images"].append(image(9))
            if state.get("drop_shared") and state["list_count"] == 2:
                state["images"] = [i for i in state["images"] if i["OwnerId"] == ACCOUNT]
            rows = state["images"]
        output = {"Images": rows}
        if state.get("bad_initial") is not None and state["list_count"] == 1 and "--image-ids" not in args:
            output = state["bad_initial"]
    elif operation == "describe-snapshots":
        snapshot = option("--snapshot-ids")
        output = {"Snapshots": [{"SnapshotId": snapshot, "OwnerId": ACCOUNT,
            "Encrypted": state.get("encrypted", False), "State": "completed"}]}
        if state.get("encrypted_after") and count > 1:
            output["Snapshots"][0]["Encrypted"] = True
        if state.get("foreign_snapshot"):
            output["Snapshots"][0]["OwnerId"] = "999900001111"
        if state.get("bad_snapshot"):
            output = {"Snapshots": []}
    elif operation == "modify-image-attribute":
        assert option("--launch-permission") == "Add=[{Group=all}]"
        assert "--attribute" not in args
        state["mutations"].append([operation, option("--image-id")])
        for row in state["images"]:
            if row["ImageId"] == option("--image-id"):
                row["Public"] = not state.get("public_unobserved", False)
                if state.get("automatic_deprecation"):
                    row["DeprecationTime"] = "2028-08-03T00:00:00Z"
    elif operation == "deregister-image":
        assert "--no-delete-associated-snapshots" in args and "--delete-associated-snapshots" not in args
        ami_id = option("--image-id")
        state["mutations"].append([operation, ami_id])
        accepted = ami_id != state.get("deregister_false")
        output = {"Return": accepted, "DeleteSnapshotResults": []}
        if accepted:
            if state.get("retain_refs"):
                for row in state["images"]:
                    if row["ImageId"] == ami_id:
                        row["State"] = "deregistered"
            else:
                state["images"] = [i for i in state["images"] if i["ImageId"] != ami_id]
        if state.get("deregister_empty"):
            output = None
        if state.get("deregister_bad_results"):
            output["DeleteSnapshotResults"] = False
    elif operation == "delete-snapshot":
        state["mutations"].append([operation, option("--snapshot-id")])
    state_path.write_text(json.dumps(state))
    if code:
        return code
    if output is not None:
        if isinstance(output, str):
            print(output)
        else:
            print(json.dumps(output))
    return 0


class AmiTaskTests(unittest.TestCase):
    def run_task(self, task, answer="y\n", **fixture):
        proof = ROOT / "tmp/kakomon10q-ami-task-pagination-fix-20261011"
        proof.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="stub-", dir=proof) as temporary:
            base = Path(temporary)
            state_path = base / "state.json"
            state = {"images": [image(3), image(1), image(2)], "calls": [], "mutations": [],
                "counts": {}, "list_count": 0, "reference_count": 0}
            state.update(fixture)
            state_path.write_text(json.dumps(state))
            stub = base / "aws"
            stub.write_text(f"#!{sys.executable}\nimport runpy, sys\nsys.argv = [{str(Path(__file__).resolve())!r}, '--aws-stub', *sys.argv[1:]]\nrunpy.run_path({str(Path(__file__).resolve())!r}, run_name='__main__')\n")
            stub.chmod(0o755)
            env = dict(os.environ, PATH=str(base) + os.pathsep + os.environ["PATH"],
                KAKOMON10_AMI_TASK_STUB_STATE=str(state_path))
            result = subprocess.run(["bash", str(ROOT / "mise-tasks/kakomon10-qualify" / task)],
                input=answer, text=True, capture_output=True, env=env, timeout=25)
            state = json.loads(state_path.read_text())
            with (proof / "stub-cases.jsonl").open("a") as output:
                output.write(json.dumps({"test": self.id(), "task": task, "exit": result.returncode,
                    "stdout": result.stdout, "stderr": result.stderr, "mutations": state["mutations"],
                    "calls": state["calls"]}) + "\n")
            return result, state

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def rejected(self, result, state, mutations=0):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(state["mutations"]), mutations)

    def test_publish_adds_only_latest_launch_permission(self):
        result, state = self.run_task("publish-latest-ami", automatic_deprecation=True)
        self.success(result)
        self.assertEqual(state["mutations"], [["modify-image-attribute", image(3)["ImageId"]]])
        self.assertIn("AMI published", result.stdout)

    def test_individual_id_lookup_has_no_service_page_limit(self):
        for task in ("publish-latest-ami", "prune-ami"):
            with self.subTest(task=task):
                result, state = self.run_task(task)
                self.success(result)
                lookups = [args for args in state["calls"] if "--image-ids" in args]
                self.assertTrue(lookups)
                self.assertTrue(all("--page-size" not in args and "--max-results" not in args for args in lookups))

    def test_invalid_id_pagination_stops_before_mutation(self):
        with tempfile.TemporaryDirectory(prefix="bad-pagination-", dir=ROOT / "tmp") as temporary:
            for task in ("publish-latest-ami", "prune-ami"):
                with self.subTest(task=task):
                    source = (ROOT / "mise-tasks/kakomon10-qualify" / task).read_text()
                    broken = Path(temporary) / task
                    broken.write_text(source.replace("--include-deprecated --include-disabled",
                        "--include-deprecated --include-disabled --page-size 100", 1))
                    result, state = self.run_task(str(broken))
                    self.rejected(result, state)
                    self.assertIn("InvalidParameterCombination", result.stderr)
                    self.assertTrue(any("--image-ids" in args and "--page-size" in args for args in state["calls"]))

    def test_publish_future_deprecation_and_tie_are_supported(self):
        rows = [image(n, CreationDate="2026-08-01T00:00:00.000Z", DeprecationTime="2099-01-01T00:00:00Z") for n in (2, 3, 1)]
        result, state = self.run_task("publish-latest-ami", images=rows)
        self.success(result)
        self.assertEqual(state["mutations"][0][1], image(3)["ImageId"])

    def test_cancel_and_eof_never_mutate(self):
        for task in ("publish-latest-ami", "prune-ami"):
            for answer in ("N\n", "", "Y\n"):
                with self.subTest(task=task, answer=answer):
                    result, state = self.run_task(task, answer=answer)
                    self.success(result)
                    self.assertEqual(state["mutations"], [])

    def test_zero_and_one_image_prune(self):
        for rows in ([], [image(3)]):
            result, state = self.run_task("prune-ami", images=rows)
            self.success(result)
            self.assertEqual(state["mutations"], [])
        result, state = self.run_task("publish-latest-ami", images=[])
        self.rejected(result, state)

    def test_amd_other_variant_foreign_and_deprecated_are_retained(self):
        rows = [image(1), image(2), image(3), image(4, Architecture="x86_64"),
            image(5, Name="isuren/kakomon10-final-arm64-5"), image(6, OwnerId="999900001111"),
            image(7, DeprecationTime="2000-01-01T00:00:00Z"), image(8, State="disabled"),
            image(9, Disabled=True)]
        result, state = self.run_task("prune-ami", images=rows)
        self.success(result)
        self.assertEqual(state["mutations"], [["deregister-image", image(n)["ImageId"]] for n in (1, 2)] +
            [["delete-snapshot", f"snap-{n:017x}"] for n in (1, 2)])

    def test_shared_snapshot_keeps_foreign_disabled_reference(self):
        foreign = image(8, OwnerId="999900001111", State="disabled", DeprecationTime="2000-01-01T00:00:00Z")
        foreign["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"] = "snap-00000000000000001"
        result, state = self.run_task("prune-ami", images=[image(3), image(2), image(1), foreign])
        self.success(result)
        self.assertNotIn(["delete-snapshot", "snap-00000000000000001"], state["mutations"])

    def test_new_reference_and_deregistered_residue_are_retained(self):
        for flag in ("new_reference", "retain_refs"):
            result, state = self.run_task("prune-ami", **{flag: True})
            self.success(result)
            self.assertEqual([m for m in state["mutations"] if m[0] == "delete-snapshot"], [])
            self.assertIn("保持するsnapshot", result.stdout)

    def test_initial_shared_snapshot_is_never_newly_added(self):
        foreign = image(8, OwnerId="999900001111")
        foreign["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"] = "snap-00000000000000001"
        result, state = self.run_task("prune-ami", images=[image(1), image(2), image(3), foreign], drop_shared=True)
        self.success(result)
        self.assertNotIn(["delete-snapshot", "snap-00000000000000001"], state["mutations"])

    def test_confirmation_changes_abort_before_mutation(self):
        for task in ("publish-latest-ami", "prune-ami"):
            result, state = self.run_task(task, changed_list=True)
            self.rejected(result, state)
        result, state = self.run_task("prune-ami", changed_target=True)
        self.rejected(result, state)

    def test_encrypted_or_missing_snapshot_blocks_publish(self):
        for flag in ("encrypted", "encrypted_after", "bad_snapshot", "foreign_snapshot"):
            result, state = self.run_task("publish-latest-ami", **{flag: True})
            self.rejected(result, state)

    def test_product_code_response_must_be_empty_array_or_absent(self):
        for codes in (False, {}, ["marketplace"]):
            result, state = self.run_task("publish-latest-ami", images=[image(3, ProductCodes=codes)])
            self.rejected(result, state)

    def test_api_failure_empty_stdout_is_not_empty_inventory(self):
        for task in ("publish-latest-ami", "prune-ami"):
            for fail in (["get-caller-identity", 1], ["describe-images", 1], ["describe-snapshots", 1]):
                result, state = self.run_task(task, fail=fail)
                self.rejected(result, state)

    def test_bad_shapes_tokens_ids_and_dates_stop(self):
        bad = [{}, {"Images": None}, {"Images": [], "NextToken": "unprocessed"}, "",
            '{"Images": []}\n{"Images": []}', {"Images": [image(1, ImageId="ami-wrong")]},
            {"Images": [image(1, CreationDate="invalid")]}, {"Images": [image(1), image(1)]}]
        for response in bad:
            result, state = self.run_task("prune-ami", bad_initial=response)
            self.rejected(result, state)

    def test_reference_failure_before_confirmation_never_mutates(self):
        result, state = self.run_task("prune-ami", reference_fail=1)
        self.rejected(result, state)

    def test_reference_failure_after_deregister_never_deletes_snapshot(self):
        result, state = self.run_task("prune-ami", reference_fail=3)
        self.rejected(result, state, mutations=2)
        self.assertTrue(all(m[0] == "deregister-image" for m in state["mutations"]))

    def test_deregister_failure_stops_all_snapshot_deletions(self):
        for fixture in ({"deregister_false": image(2)["ImageId"]}, {"fail": ["deregister-image", 2]}, {"deregister_empty": True}, {"deregister_bad_results": True}):
            result, state = self.run_task("prune-ami", **fixture)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("snapshot削除は未開始です", result.stderr)
            self.assertFalse(any(m[0] == "delete-snapshot" for m in state["mutations"]))

    def test_snapshot_delete_failure_stops_remaining_deletions(self):
        for occurrence in (1, 2):
            result, state = self.run_task("prune-ami", fail=["delete-snapshot", occurrence])
            self.rejected(result, state, mutations=2 + occurrence - 1)
            self.assertIn("snapshot削除失敗", result.stderr)
            self.assertEqual(sum(m[0] == "delete-snapshot" for m in state["mutations"]), occurrence - 1)

    def test_public_observation_required(self):
        result, state = self.run_task("publish-latest-ami", public_unobserved=True)
        self.rejected(result, state, mutations=1)
        self.assertNotIn("AMI published", result.stdout)

    def test_foreign_snapshot_is_retained(self):
        result, state = self.run_task("prune-ami", foreign_snapshot=True)
        self.success(result)
        self.assertTrue(all(m[0] == "deregister-image" for m in state["mutations"]))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--aws-stub":
        sys.exit(aws_stub())
    unittest.main(verbosity=2)
