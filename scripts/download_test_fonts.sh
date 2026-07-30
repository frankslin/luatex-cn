#!/bin/sh
# 下载回归测试所需的字体到 test/fonts/（该目录不入库）。
# regression_test.py 会将 OSFONTDIR 指向 test/fonts，luaotfload 据此解析字体名。
# 字体来源：全字庫 (CNS11643)，镜像仓库 free-fonts-npm/TW-CNS11643-Fonts，固定到 commit 以保证可复现。
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FONTS_DIR="$REPO_ROOT/test/fonts"
MIRROR="https://raw.githubusercontent.com/free-fonts-npm/TW-CNS11643-Fonts/de5bd2e37371798f996bac11ea8cf9d3a411749e/2026-05-05"

mkdir -p "$FONTS_DIR"

download() {
    name=$1
    url=$2
    if [ -s "$FONTS_DIR/$name" ]; then
        echo "已存在: $name"
    else
        echo "下载: $name"
        curl -fL --retry 3 -o "$FONTS_DIR/$name.part" "$url"
        mv "$FONTS_DIR/$name.part" "$FONTS_DIR/$name"
    fi
}

download "TW-Kai-98_1.ttf" "$MIRROR/Fonts_Kai/TW-Kai-98_1.ttf"

echo "完成。字体位于 $FONTS_DIR"
