#!/usr/bin/env python3
"""Validate every filesystem input consumed by the fixed official Go benchmark."""

import argparse
import json
from pathlib import Path

SNAPSHOT_DIRECTORIES = (
    "chair_detail", "chair_search_condition", "chair_search", "estate_detail",
    "estate_search_condition", "estate_search", "chair_low_priced", "estate_low_priced",
    "recommended_estate_with_chair", "estate_nazotte",
)


def read_records(path, expected_ids):
    if not path.is_file() or not path.stat().st_size:
        raise ValueError(f"missing or empty benchmark input: {path}")
    with path.open() as stream:
        records = [json.loads(line) for line in stream]
    if [record.get("id") for record in records] != list(expected_ids):
        raise ValueError(f"unexpected benchmark record IDs or count: {path}")
    return records


def check_benchmark_data(result_dir, fixture_dir):
    result = Path(result_dir)
    for kind in ("chair", "estate"):
        read_records(result / f"{kind}_json.txt", range(1, 29501))
        verification = read_records(result / f"verify_draft_{kind}.txt", range(29501, 30001))
        if kind == "chair" and verification[0].get("stock") != 1:
            raise ValueError("the first verification chair must have stock=1")
        drafts = result / "draft_data" / kind
        expected_names = {f"{index}.txt" for index in range(20)}
        if not drafts.is_dir() or {path.name for path in drafts.iterdir()} != expected_names:
            raise ValueError(f"incomplete benchmark draft directory: {drafts}")
        for index in range(20):
            first_id = 30001 + index * 500
            read_records(drafts / f"{index}.txt", range(first_id, first_id + 500))
        fixture = Path(fixture_dir) / f"{kind}_condition.json"
        if not fixture.is_file() or not json.loads(fixture.read_text()):
            raise ValueError(f"missing or empty benchmark fixture: {fixture}")
    for name in SNAPSHOT_DIRECTORIES:
        directory = result / "verification_data" / name
        if not directory.is_dir():
            raise ValueError(f"missing benchmark snapshot directory: {directory}")
        files = list(directory.iterdir())
        if not files:
            raise ValueError(f"empty benchmark snapshot directory: {directory}")
        for path in files:
            if not path.is_file() or not json.loads(path.read_text()):
                raise ValueError(f"missing or empty benchmark snapshot: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-dir", type=Path, required=True)
    parser.add_argument("--fixture-dir", type=Path, required=True)
    args = parser.parse_args()
    check_benchmark_data(args.result_dir, args.fixture_dir)
    print("kakomon10-qualify benchmark data: ok")


if __name__ == "__main__":
    main()
