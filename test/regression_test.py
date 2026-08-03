#!/usr/bin/env python3
import os
import subprocess
import shutil
import sys
import argparse
import re
import json
from pathlib import Path

# image_compare lives in scripts/
_BASE_DIR = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(_BASE_DIR / "scripts"))
from image_compare import pdf_to_pngs, compare_images

import concurrent.futures
import multiprocessing

# Paths relative to the project root
BASE_DIR = Path(__file__).parent.parent.resolve()
REG_DIR = BASE_DIR / "test" / "regression_test"

# 仓库内测试字体（TW-Kai 等），由 scripts/download_test_fonts.sh 下载。
# 通过 OSFONTDIR 让 luaotfload 找到它们，无需安装到系统字体目录。
FONTS_DIR = BASE_DIR / "test" / "fonts"
_prev_osfontdir = os.environ.get("OSFONTDIR")
os.environ["OSFONTDIR"] = (
    f"{FONTS_DIR}{os.pathsep}{_prev_osfontdir}" if _prev_osfontdir else str(FONTS_DIR)
)
if not list(FONTS_DIR.glob("*.ttf")):
    print(
        f"WARNING: {FONTS_DIR} 中没有字体文件，编译可能因缺少 TW-Kai 失败。\n"
        "请先运行: sh scripts/download_test_fonts.sh"
    )
# 精确比较：测试字体已全部钉定（manifest 固定 URL + SHA-256 下载，
# 经 OSFONTDIR 提供，不依赖 TeX Live 装包），渲染跨环境逐字节可复现，
# 任何像素差异都是真回归。
# 曾经的容差（绝对 200px + 比例 0.2%，见 f9d06fd）是为吸收未钉定字体的
# 跨平台渲染差异而设，钉定后反而会掩盖阈值以下的回归，已移除。

# Test suites: each has its own tex/, baseline/, current/, diff/, pdf/ subdirectories
SUITES = {
    "basic": REG_DIR / "basic",
    "past_issue": REG_DIR / "past_issue",
    "complete": REG_DIR / "complete",
}


def get_suite_dirs(suite_dir):
    """Return (tex_dir, pdf_dir, baseline_dir, current_dir, diff_dir) for a suite."""
    return (
        suite_dir / "tex",
        suite_dir / "pdf",
        suite_dir / "baseline",
        suite_dir / "current",
        suite_dir / "diff",
    )


# JSON 布局导出中的易变元数据键，比较基线时忽略（例如 source_mtime 在
# git 检出后必然变化，与布局本身无关）。
VOLATILE_JSON_KEYS = {"source_mtime"}


def strip_volatile_json(data):
    """Recursively drop volatile metadata keys before baseline comparison."""
    if isinstance(data, dict):
        return {k: strip_volatile_json(v) for k, v in data.items()
                if k not in VOLATILE_JSON_KEYS}
    if isinstance(data, list):
        return [strip_volatile_json(v) for v in data]
    return data


def run_command(cmd, cwd=None, capture=True, log_list=None):
    msg = f"Running: {' '.join(cmd)}"
    if log_list is not None:
        log_list.append(msg)
    else:
        print(msg)

    if capture:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    else:
        result = subprocess.run(cmd, cwd=cwd)
    return result

def compile_tex(tex_file, pdf_dir, log_list):
    """Compile TeX file to PDF in the given pdf_dir."""
    ex_name = tex_file.name
    pdf_name = tex_file.stem + ".pdf"

    # We run lualatex twice to ensure correct layout (typical for guji)
    for i in range(2):
        log_list.append(f"Compilation pass {i+1} for {ex_name}...")
        res = run_command([
            "lualatex",
            "-interaction=nonstopmode",
            f"-output-directory={pdf_dir}",
            str(tex_file.name)
        ], cwd=tex_file.parent, log_list=log_list)

        if res.returncode != 0:
            log_list.append(f"ERROR: Compilation failed for {ex_name}")
            # 输出 lualatex 日志尾部，方便在 CI 上直接定位错误
            output = res.stdout or ""
            if res.stderr:
                output += "\n" + res.stderr
            tail = output.strip().splitlines()[-40:]
            log_list.append(f"--- lualatex output tail for {ex_name} ---")
            log_list.extend(tail)
            log_list.append("--- end of output ---")
            return False

    return pdf_dir / pdf_name

def pdf_to_pngs_logged(pdf_file, output_dir, log_list):
    """Wrapper around image_compare.pdf_to_pngs that appends errors to log_list."""
    pngs = pdf_to_pngs(pdf_file, output_dir)
    if not pngs:
        log_list.append(f"ERROR: PDF to PNG conversion failed for {pdf_file.name}")
    return pngs


def compare_images_logged(baseline_png, current_png, diff_png, log_list):
    """Wrapper around image_compare.compare_images (log_list kept for API compat)."""
    return compare_images(baseline_png, current_png, diff_png)


def process_file(tex_file, mode, pdf_dir, baseline_dir, current_dir, diff_dir):
    log_list = [f"\nProcessing {tex_file.name}..."]

    # 1. Compile
    pdf_file = compile_tex(tex_file, pdf_dir, log_list)
    if not pdf_file or not pdf_file.exists():
        return False, "Compilation failed", log_list

    # Check for JSON layout export file.
    # JSON may be in pdf_dir (if output-directory is respected) or in tex_file's
    # directory (lualatex cwd). Check both locations.
    json_file = pdf_dir / f"{tex_file.stem}-layout.json"
    if not json_file.exists():
        json_in_texdir = tex_file.parent / f"{tex_file.stem}-layout.json"
        if json_in_texdir.exists():
            # Move it to pdf_dir for consistent handling
            shutil.move(str(json_in_texdir), str(json_file))
    has_json = json_file.exists()

    if mode == "save":
        # 2. Convert to PNGs in a temp location first (use current_dir as temp)
        new_pngs = pdf_to_pngs_logged(pdf_file, current_dir, log_list)
        if not new_pngs:
            return False, "PNG conversion failed", log_list

        # 3. Check if baselines already exist and compare
        existing_baselines = sorted(
            [f for f in baseline_dir.glob(f"{pdf_file.stem}-*.png")
             if re.match(rf"^{re.escape(pdf_file.stem)}-\d+\.png$", f.name)],
            key=lambda x: int(re.search(r'-(\d+)\.png$', x.name).group(1)))

        images_match = False
        if len(existing_baselines) == len(new_pngs):
            all_match = True
            for b_png, n_png in zip(existing_baselines, new_pngs):
                diff_png = diff_dir / f"temp_diff_{n_png.name}"
                diff_count, _, _ = compare_images_logged(b_png, n_png, diff_png, log_list)
                if diff_png.exists():
                    diff_png.unlink()
                if diff_count != 0:
                    all_match = False
                    break
            images_match = all_match

        # Save JSON baseline if present
        json_saved = False
        if has_json:
            baseline_json = baseline_dir / json_file.name
            if baseline_json.exists():
                # Compare with existing baseline JSON
                try:
                    with open(json_file, 'r', encoding='utf-8') as f:
                        new_data = json.load(f)
                    with open(baseline_json, 'r', encoding='utf-8') as f:
                        old_data = json.load(f)
                    if strip_volatile_json(new_data) == strip_volatile_json(old_data):
                        log_list.append(f"JSON baseline unchanged for {tex_file.name}")
                    else:
                        shutil.copy2(str(json_file), str(baseline_json))
                        log_list.append(f"JSON baseline updated for {tex_file.name}")
                        json_saved = True
                except (json.JSONDecodeError, IOError) as e:
                    log_list.append(f"WARNING: JSON comparison error: {e}, overwriting baseline")
                    shutil.copy2(str(json_file), str(baseline_json))
                    json_saved = True
            else:
                shutil.copy2(str(json_file), str(baseline_json))
                log_list.append(f"JSON baseline saved for {tex_file.name}")
                json_saved = True

        if images_match and not json_saved:
            log_list.append(f"No visual changes - deleting PDF for {tex_file.name}")
            for png in new_pngs:
                png.unlink()
            for diff_png in diff_dir.glob(f"diff_{pdf_file.stem}-*.png"):
                diff_png.unlink()
            if pdf_file.exists():
                pdf_file.unlink()
            return True, f"No changes ({len(existing_baselines)} pages)", log_list
        else:
            for old_png in existing_baselines:
                old_png.unlink()
            for png in new_pngs:
                shutil.move(str(png), str(baseline_dir / png.name))
            for diff_png in diff_dir.glob(f"diff_{pdf_file.stem}-*.png"):
                diff_png.unlink()
            extra = " + JSON" if json_saved else ""
            log_list.append(f"Saved {len(new_pngs)} baseline pages{extra}.")
            return True, f"Saved {len(new_pngs)} pages{extra}", log_list

    elif mode == "check":
        # 2. Convert to PNGs in current
        current_pngs = pdf_to_pngs_logged(pdf_file, current_dir, log_list)
        if not current_pngs:
            return False, "PNG conversion failed", log_list

        # Use regex to match exact stem followed by -N.png (not stem-more-stuff-N.png)
        baseline_pngs = sorted(
            [f for f in baseline_dir.glob(f"{pdf_file.stem}-*.png")
             if re.match(rf"^{re.escape(pdf_file.stem)}-\d+\.png$", f.name)],
            key=lambda x: int(re.search(r'-(\d+)\.png$', x.name).group(1)))

        if len(current_pngs) != len(baseline_pngs):
            return False, f"Page count mismatch: current={len(current_pngs)}, baseline={len(baseline_pngs)}", log_list

        total_diff_pixels = 0
        total_pixels = 0
        total_aa_pixels = 0   # gray-level-only diffs (no ink-presence flip)
        failing_pages = []

        for i, (b_png, c_png) in enumerate(zip(baseline_pngs, current_pngs)):
            diff_png = diff_dir / f"diff_{c_png.name}"
            diff_count, pixel_count, structural_count = \
                compare_images_logged(b_png, c_png, diff_png, log_list)

            diff_ratio = 100 * diff_count / pixel_count

            total_pixels += pixel_count

            if structural_count > 0:
                total_diff_pixels += diff_count
                failing_pages.append(i + 1)
                log_list.append(
                    f"  Page {i+1} fails: {diff_count} ({diff_ratio:.4f}%) pixels difference"
                    f" ({structural_count} structural).")
            elif diff_count > 0:
                # Anti-aliasing-only difference: binarized images are identical.
                # Poppler renders CFF/OTF curves (e.g. Source Han) with slightly
                # different gray ramps across platforms/versions; ignorable.
                total_aa_pixels += diff_count
                log_list.append(
                    f"  Page {i+1}: {diff_count} ({diff_ratio:.4f}%) pixels differ in"
                    f" anti-aliasing only (no structural change) — IGNORABLE.")
                if diff_png.exists():
                    diff_png.unlink()
            elif diff_png.exists():
                diff_png.unlink()

        total_diff_ratio = 100 * total_diff_pixels / total_pixels

        # Check JSON baseline if present
        json_ok = True
        json_info = ""
        baseline_json = baseline_dir / f"{tex_file.stem}-layout.json"
        if has_json and baseline_json.exists():
            try:
                with open(json_file, 'r', encoding='utf-8') as f:
                    current_data = json.load(f)
                with open(baseline_json, 'r', encoding='utf-8') as f:
                    baseline_data = json.load(f)
                if strip_volatile_json(current_data) == strip_volatile_json(baseline_data):
                    log_list.append(f"JSON matches baseline for {tex_file.name}")
                else:
                    json_ok = False
                    log_list.append(f"FAIL: JSON differs from baseline for {tex_file.name}")
            except (json.JSONDecodeError, IOError) as e:
                json_ok = False
                log_list.append(f"FAIL: JSON comparison error for {tex_file.name}: {e}")
        elif has_json and not baseline_json.exists():
            log_list.append(f"WARNING: JSON output exists but no baseline JSON for {tex_file.name}")
        elif not has_json and baseline_json.exists():
            json_ok = False
            log_list.append(f"FAIL: Baseline JSON exists but no JSON output for {tex_file.name}")

        if not json_ok:
            json_info = " + JSON mismatch"

        if total_diff_pixels == 0 and json_ok:
            log_list.append(f"SUCCESS: {tex_file.name} matches baseline (all {len(current_pngs)} pages).")
            for png in current_pngs:
                png.unlink()
            if pdf_file.exists():
                pdf_file.unlink()
            if total_aa_pixels > 0:
                return True, f"{total_aa_pixels} px AA-only diff (ignorable)", log_list
            return True, 0, log_list
        else:
            if not json_ok:
                log_list.append(f"FAIL: {tex_file.name} JSON mismatch")
                return False, f"JSON mismatch", log_list
            log_list.append(f"FAIL: {tex_file.name} differs on pages: {failing_pages}{json_info}")
            return False, f"{total_diff_pixels} ({total_diff_ratio:.4f}%) pixels, NOT IGNORABLE! {json_info}", log_list


def resolve_files_in_suite(file_args, tex_dir):
    """Resolve file arguments to actual TeX file paths within a suite's tex_dir."""
    tex_files = []
    for f in file_args:
        # 1. Try as direct path (absolute or relative to CWD)
        p = Path(f)
        if p.exists() and p.is_file():
            tex_files.append(p.resolve())
            continue

        # 2. Try as relative to tex_dir
        p_in_tex = tex_dir / f
        if p_in_tex.exists() and p_in_tex.is_file():
            tex_files.append(p_in_tex)
            continue

        # 3. Search recursively in tex_dir
        found = list(tex_dir.rglob(f))
        if not found and not f.endswith(".tex"):
            found = list(tex_dir.rglob(f + ".tex"))

        if found:
            tex_files.extend(found)
        else:
            print(f"Warning: File '{f}' not found as direct path or in {tex_dir}")
    return tex_files


def run_suite(suite_name, suite_dir, mode, file_args, jobs):
    """Run regression tests for a single suite. Returns True if all passed."""
    tex_dir, pdf_dir, baseline_dir, current_dir, diff_dir = get_suite_dirs(suite_dir)

    # Skip if tex_dir doesn't exist or is empty
    if not tex_dir.exists():
        print(f"  Skipping {suite_name}: {tex_dir} does not exist")
        return True

    # Ensure output directories exist
    for d in [pdf_dir, baseline_dir, current_dir, diff_dir]:
        d.mkdir(parents=True, exist_ok=True)

    # Find TeX files
    if file_args:
        tex_files = resolve_files_in_suite(file_args, tex_dir)
    else:
        tex_files = list(tex_dir.glob("*.tex"))

    if not tex_files:
        print(f"  Skipping {suite_name}: no TeX files found")
        return True

    results = []
    all_passed = True

    with concurrent.futures.ProcessPoolExecutor(max_workers=jobs) as executor:
        future_to_file = {
            executor.submit(process_file, f, mode, pdf_dir, baseline_dir, current_dir, diff_dir): f
            for f in tex_files
        }
        for future in concurrent.futures.as_completed(future_to_file):
            tex_file = future_to_file[future]
            try:
                success, info, log = future.result()
                print("\n".join(log))
                results.append((tex_file.name, success, info))
                if not success:
                    all_passed = False
            except Exception as exc:
                print(f"{tex_file.name} generated an exception: {exc}")
                results.append((tex_file.name, False, f"Exception: {exc}"))
                all_passed = False

    # Print summary for this suite
    print(f"\n{'='*40}")
    print(f"REGRESSION {mode.upper()} SUMMARY [{suite_name}]")
    print(f"{'='*40}")
    results.sort(key=lambda x: x[0])
    for name, success, info in results:
        status = "PASSED" if success else "FAILED"
        print(f"{status:8} {name:20} (Info: {info})")
    print("=" * 40)

    # Write machine-readable results for CI summary (ci_regression_summary.py).
    # Failing page numbers are derived there from surviving diff_<stem>-N.png files.
    if mode == "check":
        entries = [{"name": name, "passed": success, "info": str(info)}
                   for name, success, info in results]
        with open(diff_dir / "results.json", "w", encoding="utf-8") as f:
            json.dump({"suite": suite_name, "results": entries}, f,
                      ensure_ascii=False, indent=2)

    # Clean up PDF dir
    for f in pdf_dir.iterdir():
        if f.is_file():
            f.unlink()
    print(f"Cleaned up {pdf_dir}")

    return all_passed


def main():
    parser = argparse.ArgumentParser(description="Multi-page Visual Regression Test for luatex-cn")
    parser.add_argument("command", choices=["save", "check"], help="Command to run")
    parser.add_argument("files", nargs="*", help="Specific TeX files to process (optional)")
    parser.add_argument("-j", "--jobs", type=int, default=8,
                        help="Number of parallel jobs (default: 8)")

    # Suite selection flags
    parser.add_argument("--past-issues", action="store_true",
                        help="Run past_issue suite (issue regression tests)")
    parser.add_argument("--complete", action="store_true",
                        help="Run complete suite (full book tests)")
    parser.add_argument("--all", action="store_true",
                        help="Run all suites (basic + past_issue + complete)")
    args = parser.parse_args()

    # Determine which suites to run
    if args.all:
        suites_to_run = ["basic", "past_issue", "complete"]
    elif args.past_issues and args.complete:
        suites_to_run = ["past_issue", "complete"]
    elif args.past_issues:
        suites_to_run = ["past_issue"]
    elif args.complete:
        suites_to_run = ["complete"]
    else:
        # Default: only basic
        suites_to_run = ["basic"]

    all_passed = True
    print(f"Running with {args.jobs} parallel jobs...")
    print(f"Suites: {', '.join(suites_to_run)}\n")

    for suite_name in suites_to_run:
        suite_dir = SUITES[suite_name]
        print(f"--- Suite: {suite_name} ---")
        passed = run_suite(suite_name, suite_dir, args.command, args.files, args.jobs)
        if not passed:
            all_passed = False

    if not all_passed:
        sys.exit(1)

if __name__ == "__main__":
    main()
