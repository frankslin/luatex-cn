#!/bin/sh
# 下载回归测试所需字体（兼容入口，实际逻辑在 download_fonts.py）。
# 字体清单（canonical source of truth）: scripts/font-manifest.json
# 字体进入 test/fonts/（gitignored），经 OSFONTDIR 使用，不装系统字体。
set -eu
exec python3 "$(dirname "$0")/download_fonts.py" "$@"
