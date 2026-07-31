#!/usr/bin/env python3
"""几何自校验测试：竖排格内字形基线必须等距。

与像素回归测试不同，本测试不依赖基线图像——它直接解析编译产物
PDF 的内容流，取出每个字形的 Tm 定位矩阵，按列（相同 x 坐标）分组，
断言同一列内相邻字形的基线间距严格相等（即每字一格、共享基线）。

这样能抓住"「一」「丶」等墨迹不跨基线的字被按墨迹框居中而整字偏移"
一类的 bug（LEARNING.md 3.6）：那类 bug 会使列内基线间距抖动，
而基线型像素对比测试会把错误渲染原样锁进基线,无法发现。

用法：
    python3 test/geometry_test.py            # 编译并检查默认测试文件
    python3 test/geometry_test.py file.pdf   # 直接检查已有 PDF

仅用标准库（zlib/re），无第三方依赖。
"""

import os
import re
import subprocess
import sys
import tempfile
import zlib

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_TEX = os.path.join(
    REPO_ROOT, "test", "regression_test", "basic", "tex", "baseline-align.tex"
)
FONTS_DIR = os.path.join(REPO_ROOT, "test", "fonts")

# 基线间距允许的抖动（pt）。渲染只受 sp 取整影响，远小于 0.01pt；
# 墨迹框居中类 bug 造成的抖动在 1pt 以上。
TOLERANCE_PT = 0.01
# 每列至少要有这么多字形才检查（太短的列谈不上"间距序列"）
MIN_GLYPHS_PER_COLUMN = 4
# 全文档至少要找到这么多列，防止解析失败时测试空转通过
MIN_COLUMNS = 3

TM_RE = re.compile(rb"1 0 0 1 (-?[\d.]+) (-?[\d.]+) Tm\s*\[<[0-9A-Fa-f]+>\]TJ")
STREAM_RE = re.compile(rb"stream\r?\n(.*?)endstream", re.DOTALL)


def iter_content_streams(pdf_bytes):
    """遍历 PDF 里所有能解出文本的流（明文或 Flate 压缩）。"""
    for m in STREAM_RE.finditer(pdf_bytes):
        data = m.group(1)
        if b" Tm" not in data:
            try:
                data = zlib.decompress(data)
            except zlib.error:
                continue
        if b" Tm" in data:
            yield data


def collect_columns(pdf_path):
    """返回 {x坐标: [y坐标...]}，x/y 单位为 pt。"""
    with open(pdf_path, "rb") as f:
        pdf = f.read()
    columns = {}
    for stream in iter_content_streams(pdf):
        for m in TM_RE.finditer(stream):
            x, y = float(m.group(1)), float(m.group(2))
            columns.setdefault(round(x, 3), []).append(y)
    return columns


def check(pdf_path):
    columns = collect_columns(pdf_path)
    checked = 0
    failures = []
    for x, ys in sorted(columns.items(), reverse=True):
        ys = sorted(ys, reverse=True)  # 竖排自上而下
        all_gaps = [a - b for a, b in zip(ys, ys[1:])]
        if not all_gaps:
            continue
        # 同一 x 可能落着多段互不相干的列（如另一半叶的列恰好同 x）。
        # 以中位间距的 1.5 倍为界切段，段内才要求等距。
        median = sorted(all_gaps)[len(all_gaps) // 2]
        segments = [[ys[0]]]
        for prev, cur in zip(ys, ys[1:]):
            if prev - cur > median * 1.5 + TOLERANCE_PT:
                segments.append([cur])
            else:
                segments[-1].append(cur)
        for seg in segments:
            if len(seg) < MIN_GLYPHS_PER_COLUMN:
                continue
            gaps = [round(a - b, 3) for a, b in zip(seg, seg[1:])]
            ref = gaps[0]
            bad = [g for g in gaps if abs(g - ref) > TOLERANCE_PT]
            checked += 1
            if bad:
                failures.append(
                    "  x=%.3f y=%.3f..%.3f: 基线间距不一致 %s"
                    % (x, seg[0], seg[-1], gaps)
                )
    if checked < MIN_COLUMNS:
        print("FAIL: 只解析到 %d 列（最少要求 %d），PDF 解析可能失效" % (checked, MIN_COLUMNS))
        return 1
    if failures:
        print("FAIL: %d/%d 列基线间距不等距：" % (len(failures), checked))
        print("\n".join(failures))
        return 1
    print("PASS: %d 列基线间距全部等距（容差 %gpt）" % (checked, TOLERANCE_PT))
    return 0


def compile_tex(tex_path, workdir):
    env = dict(os.environ, OSFONTDIR=FONTS_DIR)
    r = subprocess.run(
        [
            "lualatex",
            "-interaction=nonstopmode",
            "-output-directory=" + workdir,
            os.path.abspath(tex_path),
        ],
        cwd=os.path.dirname(os.path.abspath(tex_path)),
        env=env,
        capture_output=True,
    )
    base = os.path.splitext(os.path.basename(tex_path))[0]
    pdf = os.path.join(workdir, base + ".pdf")
    if r.returncode != 0 and not os.path.exists(pdf):
        sys.stderr.write(r.stdout.decode(errors="replace")[-3000:])
        raise SystemExit("FAIL: 编译失败 " + tex_path)
    return pdf


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_TEX
    if target.endswith(".pdf"):
        return check(target)
    with tempfile.TemporaryDirectory() as workdir:
        return check(compile_tex(target, workdir))


if __name__ == "__main__":
    sys.exit(main())
