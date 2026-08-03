#!/usr/bin/env python3
"""标点排版审阅图：字体 × 风格 × 排向 一图尽览。

改动标点偏靠/挤压规则后，逐个打开基线图对比费时费眼。本脚本把
  {TW-Kai(楷), Source Han Serif SC(宋)} × {大陆式, 台湾式} × {竖排, 横排}
共 8 个组合各排一小页，同一段样例文本（覆盖 ，。：；？！、「」『』），
拼成一张带框带标注的审阅图。每格左上角印着模式名，肉眼扫一遍即可确认：

  - 大陆式竖排：点号偏右上（贴前字），中点类偏右直立
  - 台湾式竖排：一律居中
  - 横排：大陆式点号靠左下、台式居中（由 luatex-cn-hori 排）
  - 两种字体在同一模式下观感应一致（度量驱动的意义所在）

用法：
    python3 scripts/build/build_punct_review.py [-o 输出.png]

输出默认写到 docs/punct-review.png（入库）：改动标点规则的 PR 应
重新生成并随改动提交，review 时 diff 视图直接给出前后对照。
字体经 OSFONTDIR 指向 test/fonts/（同回归测试，无需安装系统字体）。
"""

import argparse
import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "test", "fonts")

SAMPLE = ("温故知新，可以为师。甲乙：丙丁；戊己？庚辛！「引文」既出，"
          "『书』载之。寒来暑往，秋收冬藏；闰余成岁，律吕调阳。云腾致雨？"
          "露结为霜！金生丽水，玉出昆冈。剑号巨阙，珠称夜光。")

VERT_TPL = r"""\directlua{pdf.setcompresslevel(0) pdf.setobjcompresslevel(0)}
\documentclass{%(cls)s}
\setmainfont{%(font)s}
\begin{document}
\begin{正文}
%(sample)s
\end{正文}
\end{document}
"""

HORI_TPL = r"""\directlua{pdf.setcompresslevel(0) pdf.setobjcompresslevel(0)}
\documentclass[12pt]{article}
\usepackage[paperwidth=9cm, paperheight=9cm, margin=8mm]{geometry}
\usepackage{fontspec}
\setmainfont{%(font)s}[Script=CJK, Language={Chinese Simplified}]
\usepackage{luatex-cn-hori}
\horiSetup{style=%(style)s}
\pagestyle{empty}
\begin{document}
%(sample)s
\end{document}
"""

FONTS_LIST = [
    ("楷 TW-Kai", "TW-Kai"),
    ("宋 思源宋体", "Source Han Serif SC"),
]

# (标签, 模板, 参数)
def build_matrix():
    cases = []
    for flabel, font in FONTS_LIST:
        for slabel, cls, style in [("大陆式", "ltc-cn-vbook", "mainland"),
                                   ("台湾式", "ltc-tw-vbook", "taiwan")]:
            cases.append((f"竖排·{slabel}·{flabel}",
                          VERT_TPL % {"cls": cls, "font": font, "sample": SAMPLE}))
        for slabel, style in [("大陆式", "mainland"), ("台湾式", "taiwan")]:
            cases.append((f"横排·{slabel}·{flabel}",
                          HORI_TPL % {"font": font, "style": style,
                                      "sample": SAMPLE}))
    return cases


def compile_one(tex_src, workdir, jobname):
    tex_path = os.path.join(workdir, jobname + ".tex")
    with open(tex_path, "w") as f:
        f.write(tex_src)
    env = dict(os.environ, OSFONTDIR=FONTS)
    r = subprocess.run(
        ["lualatex", "-interaction=nonstopmode", jobname + ".tex"],
        cwd=workdir, env=env, capture_output=True)
    pdf = os.path.join(workdir, jobname + ".pdf")
    if not os.path.exists(pdf):
        sys.stderr.write(r.stdout.decode("utf-8", "replace")[-2000:])
        raise SystemExit(f"编译失败：{jobname}")
    subprocess.run(["pdftoppm", "-f", "1", "-l", "1", "-r", "200", "-png",
                    pdf, os.path.join(workdir, jobname)], check=True)
    return os.path.join(workdir, jobname + "-1.png")


def crop_content(png, pdf):
    """按 PDF 字形坐标裁出正文区（竖排页面另有页眉/页码，像素裁边会
    把整页都留下来）。借用 clreq_test 的内容流解析器拿字形 bbox。"""
    from PIL import Image
    sys.path.insert(0, os.path.join(REPO, "test"))
    import clreq_test as C
    im = Image.open(png)
    s = 200 / 72.0
    H = im.size[1]
    keep = set(SAMPLE)          # 只框样例文本，排除页眉书名/页码
    xs, ys = [], []
    for line in C.parse_pdf(pdf):
        for g in line.glyphs:
            if g.char and g.char[0] in keep:
                xs += [g.x0, g.x1]
                ys += [line.y - 0.2 * g.em, line.y + g.em]
    if not xs:
        return im
    pad = 8
    box = (max(int(min(xs) * s) - pad, 0),
           max(int(H - max(ys) * s) - pad, 0),
           min(int(max(xs) * s) + pad, im.size[0]),
           min(int(H - min(ys) * s) + pad, H))
    return im.crop(box)


def find_cjk_label_font():
    for _, fname in [("k", "TW-Kai-98_1.ttf"),
                     ("s", "SourceHanSerifSC-Regular.otf")]:
        p = os.path.join(FONTS, fname)
        if os.path.exists(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output",
                    default=os.path.join(REPO, "docs", "punct-review.png"))
    args = ap.parse_args()

    from PIL import Image, ImageDraw, ImageFont

    cases = build_matrix()
    panels = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, (label, src) in enumerate(cases):
            png = compile_one(src, tmp, f"panel{i}")
            pdf = os.path.join(tmp, f"panel{i}.pdf")
            panels.append((label, crop_content(png, pdf)))
            print(f"  ✓ {label}")

    # 统一每格尺寸：等比缩放放进方框（竖排高瘦、横排宽扁，按高缩放会爆宽）
    CELL_H = 620
    scaled = []
    for label, im in panels:
        k = min(CELL_H / im.size[1], CELL_H / im.size[0])
        scaled.append((label, im.resize((max(int(im.size[0] * k), 1),
                                         max(int(im.size[1] * k), 1)))))

    COLS = 4
    label_font = None
    fp = find_cjk_label_font()
    if fp:
        label_font = ImageFont.truetype(fp, 26)
    cell_w = max(im.size[0] for _, im in scaled) + 30
    rows = (len(scaled) + COLS - 1) // COLS
    W, H = COLS * cell_w + 20, rows * (CELL_H + 70) + 20
    sheet = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(scaled):
        r, c = divmod(i, COLS)
        x = 20 + c * cell_w
        y = 20 + r * (CELL_H + 70)
        d.text((x + 4, y), label, fill=(0, 0, 0), font=label_font)
        fy = y + 40
        sheet.paste(im, (x + (cell_w - 30 - im.size[0]) // 2,
                         fy + (CELL_H - im.size[1]) // 2))
        d.rectangle((x, fy - 4, x + cell_w - 30, fy + CELL_H + 4),
                    outline=(160, 160, 160), width=2)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    sheet.save(args.output)
    print(f"审阅图：{args.output}  ({W}x{H})")


if __name__ == "__main__":
    main()
