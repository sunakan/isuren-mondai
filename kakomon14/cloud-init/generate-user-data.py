#!/usr/bin/env python3
"""kakomon14/provisioning/配下のスクリプトからcloud-config(user-data)を生成する。

provisioning/側の内容が正になるよう、write_filesの中身は都度この生成物へ反映する
(user-data.yamlを直接編集しない)。
"""

import gzip
import pathlib
import yaml

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROVISIONING_DIR = SCRIPT_DIR.parent / "provisioning"
OUTPUT_FILE = SCRIPT_DIR / "user-data.yaml"
# EC2のUser Dataはbase64エンコード後16KBまでのため、Packerのuser_data_fileには
# こちらのgzip圧縮版を渡す(EC2/cloud-initはgzipのuser-dataを自動展開する)。
OUTPUT_FILE_GZ = SCRIPT_DIR / "user-data.yaml.gz"
REMOTE_DIR = "/opt/kakomon14/provisioning"

# .shは自動収集する(新規スクリプト追加時にこのリストへの追記を忘れる事故を防ぐ)。
# READMEはプロビジョニングの実行に不要なので対象外。write_filesの配置順は実行順に影響しない
# (実行順はall.sh側が握る)ため、ソートのみで十分。
FILES = sorted(p.name for p in PROVISIONING_DIR.glob("*.sh")) + [
    "goss.yaml",
    "mise.ami.toml",
    "mise.ami.lock",
]


def build_cloud_config() -> dict:
    write_files = []
    for name in FILES:
        content = (PROVISIONING_DIR / name).read_text()
        write_files.append(
            {
                "path": f"{REMOTE_DIR}/{name}",
                "owner": "root:root",
                "permissions": "0644",
                "content": content,
            }
        )
    return {
        "write_files": write_files,
        # ENABLE_TLSは自己署名証明書生成のみでネットワーク到達性を要さないためtrue固定
        "runcmd": [
            f"env ENABLE_TLS=true bash {REMOTE_DIR}/all.sh",
        ],
    }


def main() -> None:
    cloud_config = build_cloud_config()
    body = yaml.dump(cloud_config, allow_unicode=True, sort_keys=False, width=4096)
    text = f"#cloud-config\n{body}"
    OUTPUT_FILE.write_text(text)
    print(f"wrote {OUTPUT_FILE}")
    OUTPUT_FILE_GZ.write_bytes(gzip.compress(text.encode(), compresslevel=9))
    print(f"wrote {OUTPUT_FILE_GZ}")


if __name__ == "__main__":
    main()
