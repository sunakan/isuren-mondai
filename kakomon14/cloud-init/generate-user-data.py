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

# READMEはプロビジョニングの実行に不要なので配置対象から除く
FILES = [
    "lib.sh",
    "10-base.sh",
    "20-user.sh",
    "30-runtime.sh",
    "40-mysql.sh",
    "50-source.sh",
    "60-initdb.sh",
    "70-webapp-go.sh",
    "75-matcher.sh",
    "77-payment-mock.sh",
    "80-frontend.sh",
    "90-nginx.sh",
    "95-deploy-helper.sh",
    "all.sh",
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
