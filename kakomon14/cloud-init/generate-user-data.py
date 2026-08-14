#!/usr/bin/env python3
"""kakomon14/provisioning/を実行するcloud-config(user-data)を生成する。

provisioning/配下のファイル自体はuser-dataに埋め込まず、EC2起動時にこのリポジトリ自身を
git clone(HEADのコミットに固定)して取得する。これにより埋め込み対象ファイルの手動管理
(FILESリスト)やEC2 User Dataの16KB制限回避(gzip)が丸ごと不要になる。
"""

import pathlib
import subprocess

import yaml

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_FILE = SCRIPT_DIR / "user-data.yaml"
REPO_URL = "https://github.com/sunakan/isuren-mondai.git"
CLONE_DIR = "/opt/isuren-mondai"
PROVISIONING_DIR = f"{CLONE_DIR}/kakomon14/provisioning"


def build_cloud_config() -> dict:
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return {
        # git init+remote add+fetch <SHA>+checkoutの構成にすることで、shallow(--depth 1)のまま
        # 任意のコミットを指定できる(50-source.shのsparse_checkout_fetchと同じ考え方)。
        # ENABLE_TLSは自己署名証明書生成のみでネットワーク到達性を要さないためtrue固定。
        # 本番AMIでは1回きりのプロビジョニングのため、clone自体も実行後に削除する
        # (50-source.shのcleanup_checkoutsと同じ理由: ディスク使用量・古い設定混入リスクを避ける)。
        "runcmd": [
            f"git init --quiet {CLONE_DIR}",
            f"git -C {CLONE_DIR} remote add origin {REPO_URL}",
            f"git -C {CLONE_DIR} fetch --quiet --depth 1 origin {commit}",
            f"git -C {CLONE_DIR} checkout --quiet {commit}",
            f"env ENABLE_TLS=true bash {PROVISIONING_DIR}/all.sh",
            f"rm -rf {CLONE_DIR}",
        ],
    }


def main() -> None:
    cloud_config = build_cloud_config()
    body = yaml.dump(cloud_config, allow_unicode=True, sort_keys=False, width=4096)
    text = f"#cloud-config\n{body}"
    OUTPUT_FILE.write_text(text)
    print(f"wrote {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
