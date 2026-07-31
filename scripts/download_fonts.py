#!/usr/bin/env python3
"""按 scripts/font-manifest.json 下载项目字体到仓库内目录（不装系统字体）。

用法:
    python3 scripts/download_fonts.py            # 下载 required 字体（测试必需）
    python3 scripts/download_fonts.py --all      # 连同 optional（Ext-B/Plus 等）
    python3 scripts/download_fonts.py --verify   # 只校验已下载文件的 SHA-256

字体放入 manifest 的 font_dir（默认 test/fonts/，gitignored），使用时通过
OSFONTDIR 指向该目录（regression_test.py 已自动处理）。每个文件下载后校验
SHA-256，与 manifest 不符即报错退出——保证任何环境拿到的字节完全一致。
"""
import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).resolve().parent / "font-manifest.json"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, dest):
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"下载: {url}")
    with urllib.request.urlopen(url, timeout=120) as resp, open(tmp, "wb") as out:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
    tmp.rename(dest)


def extract_from_archive(archive, member, dest, font_dir):
    """从 zip 压缩包中解出字体文件。压缩包按 sha256 缓存复用。"""
    import zipfile

    cache_dir = font_dir / ".archives"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached = cache_dir / (archive["sha256"][:16] + ".zip")
    if not (cached.exists() and sha256_of(cached) == archive["sha256"]):
        download(archive["url"], cached)
        actual = sha256_of(cached)
        if actual != archive["sha256"]:
            cached.unlink()
            raise RuntimeError(
                f"压缩包 sha256 不符: 期望 {archive['sha256']} 实际 {actual}")
    with zipfile.ZipFile(cached) as zf:
        with zf.open(archive.get("member", member)) as src, open(dest, "wb") as out:
            while True:
                chunk = src.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--all", action="store_true", help="包含 optional 字体")
    ap.add_argument("--verify", action="store_true", help="只校验，不下载")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    font_dir = REPO_ROOT / manifest["font_dir"]
    font_dir.mkdir(parents=True, exist_ok=True)

    failures = []
    for font in manifest["fonts"]:
        optional = font.get("required_for") == ["optional"]
        if optional and not (args.all or args.verify):
            continue
        dest = font_dir / font["file"]

        if dest.exists():
            actual = sha256_of(dest)
            if actual == font["sha256"]:
                print(f"已就绪: {font['file']} (sha256 OK)")
                continue
            if args.verify:
                failures.append(f"{font['file']}: sha256 不符 {actual}")
                continue
            print(f"哈希不符，重新下载: {font['file']}")
            dest.unlink()
        elif args.verify:
            if not optional:
                failures.append(f"{font['file']}: 缺失")
            continue

        archive = font.get("archive")
        if archive:
            # zip 分发的字体：下载（或复用）压缩包，校验后解出成员文件。
            # 压缩包按其 sha256 缓存在 font_dir/.archives/，同包多字体只下一次。
            try:
                extract_from_archive(archive, font["file"], dest, font_dir)
            except Exception as e:  # noqa: BLE001
                failures.append(f"{font['file']}: 压缩包获取失败 ({e})")
                continue
        else:
            for url in font["urls"]:
                try:
                    download(url, dest)
                    break
                except Exception as e:  # noqa: BLE001 - 尝试下一个镜像
                    print(f"  失败 ({e})，尝试下一个源...", file=sys.stderr)
            else:
                failures.append(f"{font['file']}: 所有下载源均失败")
                continue

        actual = sha256_of(dest)
        if actual != font["sha256"]:
            dest.unlink()
            failures.append(
                f"{font['file']}: 下载内容 sha256 不符\n"
                f"  期望 {font['sha256']}\n  实际 {actual}"
            )
        else:
            print(f"完成: {font['file']} (sha256 OK)")

    if failures:
        print("\nERROR:", file=sys.stderr)
        for f in failures:
            print("  " + f, file=sys.stderr)
        sys.exit(1)
    print(f"\n字体位于 {font_dir}")


if __name__ == "__main__":
    main()
