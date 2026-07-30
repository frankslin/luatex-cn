#!/usr/bin/env python3
"""生成回归测试的 GitHub Actions Step Summary。

在 `regression_test.py check` 之后运行（CI 中 `if: always()`）：

1. 读取各套件 diff/results.json（regression_test.py 写出）
2. 输出 Markdown 一览表（✅/❌）到 $GITHUB_STEP_SUMMARY（无此环境变量时打印到
   stdout，便于本地预览）
3. 对每个失败用例：定位失败页（diff/ 中残留的 diff_<名>-<页>.png 即失败页），
   计算差异像素的聚类区域，用九宫格方位（右上/中部/左下……竖排书右侧为卷首）
   描述"哪里变了"，并生成「基线 | 当前 | 差异标注」三联对比图
   diff/summary_<名>-<页>.png（当前页上用红框圈出差异区域），供 artifact 下载。

GitHub Step Summary 不渲染本地文件/base64 图片，所以对比图放 artifact，
summary 里给出文字定位 + 指引。
"""

import json
import os
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

TEST_DIR = Path(__file__).parent / "regression_test"
SUITES = ["basic", "past_issue", "complete"]

# 差异像素判定阈值。compare_images 用精确不等（任何 1 级色差都算），
# 这里稍放宽以聚焦可见差异；显著性另由 MIN_REGION_PIXELS 控制
PIXEL_TOLERANCE = 30
# 聚类网格：把页面划成 GRID×GRID 块，相邻含差异的块合并为一个区域
GRID = 48
# 报告的最大区域数（其余合并计入"另有 N 处"）
MAX_REGIONS = 4
# 小于该像素数的区域视为微小散点（抗锯齿噪声等），只汇总数量不逐一定位
MIN_REGION_PIXELS = 500

# 九宫格方位名（页面图像的视觉方位：x 小为左，y 小为上）
POS_NAMES = [["左上", "中上", "右上"],
             ["左中", "中部", "右中"],
             ["左下", "中下", "右下"]]


def diff_mask(baseline, current):
    """返回逐块布尔矩阵 [GRID][GRID]：该块内是否有超阈值差异像素，
    以及精确差异 bbox 列表来源的逐块差异计数。"""
    import numpy as np
    b = np.asarray(baseline.convert("RGB"), dtype=int)
    c = np.asarray(current.convert("RGB"), dtype=int)
    if b.shape != c.shape:
        h = min(b.shape[0], c.shape[0])
        w = min(b.shape[1], c.shape[1])
        b, c = b[:h, :w], c[:h, :w]
    mask = (abs(b - c) > PIXEL_TOLERANCE).any(axis=2)
    return mask


def cluster_regions(mask):
    """把差异 mask 按 GRID×GRID 分块，BFS 合并相邻差异块，
    返回 [(x0,y0,x1,y1, pixel_count)]，坐标为原图像素，按差异量降序。"""
    h, w = mask.shape
    bh, bw = max(1, h // GRID), max(1, w // GRID)
    blocks = {}
    ys, xs = mask.nonzero()
    for y, x in zip(ys.tolist(), xs.tolist()):
        blocks.setdefault((y // bh, x // bw), []).append((y, x))

    seen = set()
    regions = []
    for start in blocks:
        if start in seen:
            continue
        queue = [start]
        seen.add(start)
        pts = []
        while queue:
            cell = queue.pop()
            pts.extend(blocks[cell])
            cy, cx = cell
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1),
                           (cy - 1, cx - 1), (cy - 1, cx + 1),
                           (cy + 1, cx - 1), (cy + 1, cx + 1)):
                if (ny, nx) in blocks and (ny, nx) not in seen:
                    seen.add((ny, nx))
                    queue.append((ny, nx))
        rys = [p[0] for p in pts]
        rxs = [p[1] for p in pts]
        regions.append((min(rxs), min(rys), max(rxs), max(rys), len(pts)))
    regions.sort(key=lambda r: -r[4])
    return regions


def describe_region(x0, y0, x1, y1, w, h):
    """区域中心的九宫格方位 + 页面百分比范围。"""
    cx, cy = (x0 + x1) / 2 / w, (y0 + y1) / 2 / h
    name = POS_NAMES[min(2, int(cy * 3))][min(2, int(cx * 3))]
    return "%s (横 %d–%d%%, 纵 %d–%d%%)" % (
        name, 100 * x0 // w, 100 * x1 // w + 1, 100 * y0 // h, 100 * y1 // h + 1)


def make_composite(baseline, current, regions, out_path):
    """基线 | 当前(红框标注) | 像素差热区 三联图，等比缩到总宽 ~2400px。"""
    b = baseline.convert("RGB")
    c = current.convert("RGB")
    annotated = c.copy()
    draw = ImageDraw.Draw(annotated)
    lw = max(3, b.width // 400)
    for x0, y0, x1, y1, _ in regions:
        pad = lw * 2
        draw.rectangle([x0 - pad, y0 - pad, x1 + pad, y1 + pad],
                       outline=(255, 0, 0), width=lw)
    import numpy as np
    mask = diff_mask(b, c)
    heat = np.full((*mask.shape, 3), 255, dtype="uint8")
    heat[mask] = (255, 0, 0)
    heat_im = Image.fromarray(heat)

    gap = 12
    total_w = b.width + annotated.width + heat_im.width + gap * 2
    comp = Image.new("RGB", (total_w, b.height), (64, 64, 64))
    comp.paste(b, (0, 0))
    comp.paste(annotated, (b.width + gap, 0))
    comp.paste(heat_im, (b.width + annotated.width + gap * 2, 0))
    if comp.width > 2400:
        comp.thumbnail((2400, 10 ** 6))
    comp.save(out_path)


def summarize_suite(suite, lines):
    diff_dir = TEST_DIR / suite / "diff"
    baseline_dir = TEST_DIR / suite / "baseline"
    current_dir = TEST_DIR / suite / "current"
    results_file = diff_dir / "results.json"
    if not results_file.exists():
        return False
    data = json.loads(results_file.read_text(encoding="utf-8"))
    results = sorted(data["results"], key=lambda r: (r["passed"], r["name"]))
    n_fail = sum(1 for r in results if not r["passed"])

    lines.append("")
    lines.append("## %s 套件 [%s]" % ("❌" if n_fail else "✅", suite))
    lines.append("")
    lines.append("| 测试 | 状态 | 说明 |")
    lines.append("|---|---|---|")
    for r in results:
        mark = "✅" if r["passed"] else "❌"
        info = r["info"] if r["info"] not in ("0", "") else "与基线一致"
        lines.append("| %s | %s | %s |" % (r["name"], mark, info))

    # 失败详情：定位每个失败页的差异区域
    for r in results:
        if r["passed"]:
            continue
        stem = re.sub(r"\.tex$", "", r["name"])
        diff_pages = sorted(
            diff_dir.glob("diff_%s-*.png" % stem),
            key=lambda p: int(re.search(r"-(\d+)\.png$", p.name).group(1)))
        if not diff_pages:
            lines.append("")
            lines.append("### ❌ %s" % r["name"])
            lines.append("")
            lines.append("无差异图（编译失败 / 页数不匹配 / JSON mismatch，见日志）。")
            continue
        lines.append("")
        lines.append("### ❌ %s — 哪里变了" % r["name"])
        lines.append("")
        lines.append("| 页 | 差异区域（九宫格视觉方位） |")
        lines.append("|---|---|")
        for diff_png in diff_pages:
            page = re.search(r"-(\d+)\.png$", diff_png.name).group(1)
            page_name = diff_png.name[len("diff_"):]
            b_path = baseline_dir / page_name
            c_path = current_dir / page_name
            if not (b_path.exists() and c_path.exists()):
                lines.append("| %s | (缺基线或当前图) |" % page)
                continue
            baseline = Image.open(b_path)
            current = Image.open(c_path)
            regions = cluster_regions(diff_mask(baseline, current))
            major = [r for r in regions if r[4] >= MIN_REGION_PIXELS]
            minor = [r for r in regions if r[4] < MIN_REGION_PIXELS]
            shown = major[:MAX_REGIONS]
            parts = [
                describe_region(x0, y0, x1, y1, baseline.width, baseline.height)
                for x0, y0, x1, y1, _ in shown]
            if len(major) > MAX_REGIONS:
                parts.append("另有 %d 处显著区域" % (len(major) - MAX_REGIONS))
            if minor:
                parts.append("微小散点 %d 处（共 %d px）"
                             % (len(minor), sum(r[4] for r in minor)))
            desc = "；".join(parts) if parts else "（仅微小差异）"
            make_composite(baseline, current, shown,
                           diff_dir / ("summary_" + page_name))
            lines.append("| %s | %s |" % (page, desc))
        lines.append("")
        lines.append("> 🖼 三联对比图（基线 | 当前·红框标注 | 差异热区）："
                     "artifact **regression-diffs** 中的 `%s/diff/summary_%s-页.png`"
                     % (suite, stem))
    return True


def main():
    lines = ["# 回归测试报告"]
    any_suite = False
    for suite in SUITES:
        if summarize_suite(suite, lines):
            any_suite = True
    if not any_suite:
        lines.append("")
        lines.append("（未找到任何套件的 results.json——regression_test.py 未运行？）")

    out = "\n".join(lines) + "\n"
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write(out)
        print("Summary written to $GITHUB_STEP_SUMMARY")
    else:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
