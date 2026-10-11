#!/usr/bin/env python3
"""Add omitted draft verification files only after all regenerated data matches."""

import argparse
import hashlib
from pathlib import Path
import re
import shutil
import tarfile
import tempfile

from benchmark_data import check_benchmark_data


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def manifest_files(root):
    return sorted(path for path in root.rglob("*") if path.is_file() and path != root / "MANIFEST.sha256")


def verify_manifest(root):
    expected = {}
    for line in (root / "MANIFEST.sha256").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
        if not match:
            raise ValueError("invalid base Release manifest")
        sha, name = match.groups()
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or name in expected:
            raise ValueError("invalid or duplicate base Release manifest path")
        if digest(root / relative) != sha:
            raise ValueError(f"base Release checksum mismatch: {name}")
        expected[name] = sha
    actual = {str(path.relative_to(root)) for path in manifest_files(root)}
    if actual != set(expected):
        raise ValueError("base Release manifest does not cover all files")
    return expected


def repair_archive(base_archive, base_sha256, base_tag, generated_result, output):
    base_archive, generated_result, output = map(Path, (base_archive, generated_result, output))
    if output.resolve() == base_archive.resolve():
        raise ValueError("the existing Release archive must not be overwritten")
    if not re.fullmatch(r"[0-9a-f]{64}", base_sha256) or digest(base_archive) != base_sha256:
        raise ValueError("base Release archive checksum mismatch")
    if not re.fullmatch(r"kakomon10-qualify-frontend-v[0-9]+\.[0-9]+\.[0-9]+", base_tag):
        raise ValueError("invalid base Release tag")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".benchmark-repair-", dir=output.parent) as stage:
        root = Path(stage) / "release"
        root.mkdir()
        with tarfile.open(base_archive, "r:gz") as archive:
            if any(not (entry.isfile() or entry.isdir()) for entry in archive.getmembers()):
                raise ValueError("unexpected non-regular base Release entry")
            archive.extractall(root, filter="data")
        frozen = verify_manifest(root)
        for name in ("LICENSE", "public/index.html"):
            if name not in frozen:
                raise ValueError(f"missing base Release input: {name}")
        pairs = {
            "mysql/1_DummyEstateData.sql": "1_DummyEstateData.sql",
            "mysql/2_DummyChairData.sql": "2_DummyChairData.sql",
            "fixture/chair_condition.json": "chair_condition.json",
            "fixture/estate_condition.json": "estate_condition.json",
            "initial-data-result/chair_json.txt": "chair_json.txt",
            "initial-data-result/estate_json.txt": "estate_json.txt",
        }
        for kind in ("chair", "estate"):
            old_drafts = root / "initial-data-result/draft_data" / kind
            new_drafts = generated_result / "draft_data" / kind
            expected = {f"{index}.txt" for index in range(20)}
            if ({path.name for path in old_drafts.iterdir()} != expected or
                    {path.name for path in new_drafts.iterdir()} != expected):
                raise ValueError(f"regenerated draft file set differs: {kind}")
            for name in expected:
                pairs[f"initial-data-result/draft_data/{kind}/{name}"] = f"draft_data/{kind}/{name}"
        for old_name, new_name in pairs.items():
            if digest(root / old_name) != digest(generated_result / new_name):
                raise ValueError(f"regenerated data differs from the frozen Release: {old_name}")
        for kind in ("chair", "estate"):
            name = f"verify_draft_{kind}.txt"
            target = root / "initial-data-result" / name
            if target.exists():
                raise ValueError(f"base Release already contains {name}")
            shutil.copyfile(generated_result / name, target)
            target.chmod(0o644)
        check_benchmark_data(root / "initial-data-result", root / "fixture")
        (root / "BENCHMARK-REPAIR.txt").write_text(
            f"base_release_tag={base_tag}\nbase_archive_sha256={base_sha256}\n"
            "official_commit=7e6b6cfb672cde2c57d7b594d0352dc48ce317df\n"
            "generator=official make_chair_data.py + make_estate_data.py; Faker 4.1.1; seed 19700101\n"
            "preserved=all original files; frontend and verification snapshots unchanged\n"
            "added=initial-data-result/verify_draft_chair.txt,initial-data-result/verify_draft_estate.txt\n"
        )
        for name, sha in frozen.items():
            if digest(root / name) != sha:
                raise ValueError(f"a preserved Release file changed: {name}")
        (root / "MANIFEST.sha256").write_text("".join(
            f"{digest(path)}  {path.relative_to(root)}\n" for path in manifest_files(root)
        ))
        candidate = Path(stage) / output.name
        with tarfile.open(candidate, "w:gz") as archive:
            for path in sorted(root.rglob("*")):
                archive.add(path, arcname=str(path.relative_to(root)), recursive=False)
        candidate.replace(output)
    Path(str(output) + ".sha256").write_text(f"{digest(output)}  {output.name}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-archive", required=True, type=Path)
    parser.add_argument("--base-sha256", required=True)
    parser.add_argument("--base-tag", required=True)
    parser.add_argument("--generated-result", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repair_archive(args.base_archive, args.base_sha256, args.base_tag, args.generated_result, args.output)
    print(f"repaired benchmark data without frontend/snapshot rebuild: {args.output}")


if __name__ == "__main__":
    main()
