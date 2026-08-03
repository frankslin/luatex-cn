# 竖排接线设计：`shared/adjust.lua` → `flush_buffer`（P2 第一步）

> 对应规划：`docs/CLREQ-GAP-ANALYSIS.md` P2「弹性行内调整引擎接线」。
> 本文只解决一个问题——**列级调用求解器时，gap 从哪里来、target 怎么算**。
> 这是检验 H0 接口的地方：如果 `adjust.solve` 的入参在竖排凑不出来，
> 说明接口有缺口，应改共享层而不是在后端打补丁（HR5）。

> **状态（2026-08-03）：已实现。** 第 5 节的第 1–4 步已落地（见各步的
> 完成记录），第 5 步「grid 模式合流」经评估**不做**，理由见该步。
> §6 的四项接口缺口全部结清。
>
> 落地后的验收：unit 41 全过、clreq 断言 97 全过（新增 2 条行首夹注符号
> 条款）、regression 三套 43 全过，**`ltc-guji` 系列基线零变化**（R5）；
> 变的只有 `ltc-cn-vbook` / `ltc-tw-vbook` 六个用例，差异来源逐列核对过，
> 全部是本设计要的两项改变：①段末列不再均排；②挤压按 clreq 优先顺序
> （先收标点空白，字距是最后手段）。

前置状态（本设计文档写作时）：P1 第一步已完成——标点宽度调整改为上下文
相关，规则在 `tex/shared/luatex-cn-punct-squeeze.lua`，收回量由
`punct.flatten` 写在 `ATTR_PUNCT_SQUEEZE` 上，layout 阶段据此缩短字幅。
**其中「行首/行尾」这一半没有实现**，因为断列结果在 flatten 阶段还不知道——
它正是本设计要接的那一步。

---

## 1. 现状：flush_buffer 里那套临时策略（已被本设计替换）

> 本节描述的是接线**之前**的实现，保留下来是为了说明这次改的是什么。
> 当前代码里三分支已不存在，取而代之的是 `build_column_gaps` + `adjust.solve`。


`tex/core/luatex-cn-layout-grid.lua`：

| 位置 | 内容 |
|------|------|
| `flush_buffer(col_buffer, ctx, grid_height, distribute, layout_map)` :1838 | 列缓冲落盘：定位、footnote marker 组、导出 layout_map |
| natural 模式重排块 :1918–2059 | 本设计要替换的部分 |

现有模型是「**每字一个 cell + 字间一个 gap**」：

- `e.cell_height`：该字占的纵向尺寸（P1 之后已含标点收回量）；
- 字间 gap 分四类：marker 组内（0，刚性）、marker 边界（固定 0.1em）、
  block（固定 0.1em）、正文字间（基准 0.1em，可伸缩）；
- 分配策略是三分支的经验规则：
  1. `remaining < 0`（禁则挤进导致超长）→ 把可伸缩 gap **平均**压到装下为止；
  2. `0 ≤ remaining < 一个字幅` → 把余量**平均**拉伸到可伸缩 gap；
  3. 否则 → 一律 0.1em。

问题正是 clreq 差距分析第 4.2 节第 4 条：**没有优先级**。压缩时逗号空白、
中西间距、夹注符号空白、字间距被一视同仁地平均处理，而 clreq 规定的是
7 级挤压 / 2 级拉伸 + 兜底均分。`shared/adjust.lua` 就是那套顺序。

---

## 2. gap 从哪里来

### 2.1 模型转换：字幅里的空白升格为 gap

现在标点的可调空白被折进 `cell_height`（P1 把收回量算好后一次性扣掉）。
接线后改为**cell 只留刚性部分，空白全部升格为 gap**：

```
          ┌─ head gap ─┐┌── cell ──┐┌─ tail gap ─┐
直排一个字：  可调空白      字面墨迹        可调空白
```

对每个 `col_buffer[i]`（字号 `em_i`，由该 entry 的 font size 决定——natural
模式下夹注/批注字号不同，**不能用列的 grid_height 统一换算**）：

- `head_i, tail_i = punct_squeeze.blanks(char_i, opts)`（em）→ 乘 `em_i` 得 sp；
- 刚性 cell：`cell_i = advance_i − (head_i + tail_i) * em_i`；
- 字间另有一个 `fallback` gap（现行 0.1em 基准，`stretch_class = nil`、
  `fallback = true`），保持现在的密排观感。

于是一列的 gap 序列为（N 个字）：

```
[head_1] cell_1 [tail_1 | inter_1] cell_2 [tail_2 | inter_2] … cell_N [tail_N]
```

`tail_i` 与 `inter_i` 是**同一处边界上的两个 gap**，传给 solver 时合并成
一项更稳妥：`width = tail_i + head_{i+1} + 0.1em`，其 `min` 为 `0.1em`
（空白全收回）、`max` 为 `width + 拉伸上限`。合并后每列的 gap 数 = N+1
（含列首 `head_1`、列末 `tail_N`）。

### 2.2 每个 gap 的字段怎么填

`adjust.solve` 只认字段，不查表（契约 2.2）。后端按下表填：

| 字段 | 来源 |
|------|------|
| `width` | 理想值：两侧空白之和 + 0.1em 字间基准 |
| `min` | `width − 可收回空白`（可收回量由 `punct_squeeze` 判定，见 2.3） |
| `max` | 西文词距/中西间距至半字宽；其余 = `width`（不可拉） |
| `shrink_class` | `punct_table.shrink_class_of(char, style, "vertical")`；两侧都有取**较大贡献方**（与横排 `hori-spacing` 一致） |
| `stretch_class` | 仅 `western_word` / `cjk_western` |
| `fallback` | 汉字—汉字边界为 `true`，刚性单元内部为 `false` |

刚性单元（`kinsoku.no_break_between` 返回 `unbreakable_pair` / `digit_run` /
`digit_suffix` / `sign_prefix` / `currency` / `western_word`，以及 footnote
marker 组内部）：`shrink_class = nil`、`stretch_class = nil`、
`fallback = false`、`min = max = width`。横排已用同一套 `RIGID_REASONS`
（`hori-spacing.lua`），竖排照抄常量而不是重写规则。

**实现**：layout 阶段拿不到逻辑码位（竖排字形已被替换成 PUA/vert 形），
所以判定放在 `punct.flatten`——它手上有完整的逻辑码位序列，对每个边界调
`kinsoku.no_break_between`，命中 RIGID_REASONS 就在**后一个字**上打
`ATTR_RIGID_PREV`。`build_column_gaps` 见到这个标记就把该边界上的三个 gap
（前字末端空白、字距、后字始端空白）一起锁死。

### 2.3 行首/行尾在这里落地

`punct_squeeze.plan` 的 `ctx = { at_line_start, at_line_end }` 目前无人传——
flush_buffer 正是唯一知道答案的地方：`col_buffer[1]` 就在列首，
`col_buffer[N]` 就在列尾。于是：

- `head_1`：若首字是开始夹注符号且 `line_start_bracket = trim` →
  `min = 0`（整段空白可收回）；
- `tail_N`：若末字是点号且 `line_end_punct = compress` →
  `min = 0`，且该 gap 的 `shrink_class = "line_end_punct"`（挤压第 1 级）；
  开启悬挂时改为 `width = 0` 并给 render 阶段留出「整字悬于版口外」的标记。

相邻标点（P1 已实现的那一半）保持由 flatten 预判，flush 阶段只在
`min` 上叠加行首/行尾，两者取更小的 `min`（收回量取大者，与
`punct_squeeze.plan` 内「行首/行尾覆盖相邻分摊量」的语义一致）。

---

## 3. target 怎么算

```
target = ctx.col_height_sp − col_start_y
```

`col_start_y` 已含列首缩进与 padding（现行代码同名变量），因此 target 就是
这一列**实际可用的纵向长度**。但**不是每一列都该均排**：

| 列的成因 | target | 理由 |
|----------|--------|------|
| 正常写满后换列（`should_wrap`） | `col_height_sp − col_start_y` | 列满，挤压/拉伸都可能发生 |
| 禁则「挤进」导致超长 | 同上 | 超长量由 SHRINK_ORDER 逐级消化，替换现行「平均压缩」 |
| 段末列 / `\par` 或换页强制结束的列 | `Σwidth`（自然长度） | clreq：正文末行不均排（横排已按此口径，见 commit 73acb62） |
| `distribute` 模式（textbox 均分） | 保持现行分布逻辑 | 与 clreq 行内调整无关，不接入 |
| grid 模式（`default_cell_height` 非空） | 不调用 solver | 固定格 = shrink/stretch 均为 0 的退化情形（R1） |

段末列的判定：flush_buffer 需要知道「这次 flush 是因为写满换列，还是因为
段落/页面结束」。现在 `flush_fn()` 在两种情形下都被调用，**要加一个参数**
（如 `flush_buffer(..., reason)`，`reason = "wrap" | "end"`），这是本次接线
唯一需要改的调用协议。

**实现**：`do_flush(reason)` 缺省为 `"end"`，只有四个真正「写满」的点传
`"wrap"`——节点前换列（`should_wrap_before_node`，这是主路径）、字形放置时
的换列（`should_wrap`）、禁则推出、以及空白累积溢出列高。强制换列/换页、
表格单元、段落收尾一律 `"end"`。找漏这些点的症状很直白：整篇文档的字距
从「拉伸到列底」退回基准 0.1em，每列短一小截。

余量为负且全组触底时 `solve` 返回 `deficit > 0`：按 clreq「先挤进，后推出」，
此时应把末字推到下一列并重解，而不是硬压——推出决策留在后端
（`kinsoku.check_wrap` 已提供判定，代价比较仍是后端职责，契约 3.1）。

---

## 4. 落盘：从 solve 结果回写 y_sp

`solve` 返回 `widths[]`（与 gaps 等长）。位置由前缀和得到：

```
y = col_start_y + widths[1]              -- 列首 head gap
for i = 1..N:
    col_buffer[i].y_sp = y
    col_buffer[i].cell_height = cell_i    -- 刚性部分
    y = y + cell_i + widths[i+1]
```

注意 `cell_height` 此后是**刚性墨迹尺寸**，不再等于「字幅」。render 阶段
用它做居中（`punct.render` 的偏靠偏移、`calc_grid_position` 的居中）时，
必须同时知道该字的 head/tail 收回量才能把字面放对——**这一步 P1 已经踩过**：
只传总收回量会让居中逻辑把句号向上飘半个收回量、紧贴前字，后侧反而留洞。
现行做法是 render 读 `ATTR_PUNCT_SQUEEZE`（总量）与
`ATTR_PUNCT_SQUEEZE_HEAD`（始端量），按**原始满幅**居中、再按始端量上移
（`render-page-process.lua`）。

**接线后**收回量由求解器决定、不再是每字一个常量，于是随 layout_map entry
下发 `punct_squeeze_sp` / `punct_head_sp`（sp），`punct_ink_placement` 优先
读它们、没有才回落到属性（grid 模式仍走属性）。render 仍只读不算。

落盘时有个必须守住的次序：**刚性尺寸要在扣除硬性收回之前定下**。
`rigid = cell − 弹性始端 − 弹性末端` 算完之后才能把行首/行尾的硬性收回从
空白里扣掉；反过来先扣、再拿 `cell − 空白` 求刚性，刚性就会凭空变大，
整个字面被往后推半字（实测：列末句号的字面下移 0.25 em）。收回的是空白，
不是墨迹——墨迹尺寸永远等于 `em × (1 − 潜在空白)`。

同理，所有比例（潜在空白、已收回量）的基准 em 必须取**字号**
（样式字号 → 字体字号 → 正文网格，与 `get_cell_height` 同一口径），
不能图省事用已经扣过收回量的 `cell_height`：拿半字幅的句号当基准会让
`ink_h` 算成 0.75 em，字面在格中居中时偏移 1/8 em。

---

## 5. 迁移步骤（每步独立可测）

1. ~~**只读接线**~~ → **已并入第 2/3 步**：组装与落盘同时上线，差异用
   「同一份 .tex 在新旧代码下逐字对比 PDF 坐标」核对（脚本比只读日志更
   直接：`clreq_test.parse_pdf_vertical` 解析出的每字基线可直接 diff）。
2. ~~**换掉「超长」分支**~~ → **已完成**：`remaining < 0` 时走 `solve`，
   按 SHRINK_ORDER 逐级消化。效果可见：史记用例里原本被平均压缩的列，
   现在字距保持 0.1em 不动，超长量全由三个逗号的字面空白吸收。
3. ~~**换掉「近满」分支**~~ → **已完成**：拉伸走 STRETCH_ORDER + 兜底均分，
   并按 §3 只对 `reason = "wrap"` 的列均排。均排另加一条护栏：剩余量
   ≥ 一个字幅时不均排——列尾被夹注/标号组这类整块元素挡住而空出一大截时，
   硬拉到列底会把字距拉散。
4. ~~**行首/行尾接入**~~ → **已完成**：clreq 的行首开始夹注符号、行末点号
   收回是**硬性**的（不是弹性余量），但「在不在列首列末」要等断列结果，
   故由 `punct.flatten` 预先把两种情形的增量算好写在
   `ATTR_PUNCT_TRIM_START` / `ATTR_PUNCT_TRIM_END`，flush_buffer 定下断列
   后按位置取用（§2.3）。列末标点余下的空白归入挤压第 1 级
   `line_end_punct`。
5. **grid 模式合流** → **评估后不做**。grid 模式的 y 坐标是**遍历时**逐字
   落定的，中途会被 `move_to_next_valid_position` 打断——版心列、被 textbox
   占用的格子都会让同一列内的 y 出现跳变。合流意味着 flush_buffer 要重新
   复现这些跳变，而收益为零：grid 模式下 cells 固定、gaps 全 0，走求解器
   得到的坐标与现在逐字落定的完全相同。风险全在 `ltc-guji`（项目主用途）
   的主路径上，收益只有「少一条代码路径」。R2 双轨保留，理由记在此处。

每步的验收都是同一组：`texlua test/run_all.lua` → `python3
test/clreq_test.py`（竖排断言用例 `test/clreq_test/vert-punct.tex`）→
`python3 test/regression_test.py check --all`，且 `ltc-guji` 三套基线
零变化（R5）。

---

## 6. 已知的接口缺口（做之前先在共享层补）

- ~~`adjust.solve` 的 `deficit > 0` 只报告不决策~~ → **已补**：
  `kinsoku.resolve_overflow(cands)`。原文说「横排也各写一份」不准确——
  横排根本没写，它把推出/挤进交给 TeX 断行器（`hori-spacing.boundary()`
  只发 penalty + glue）；写了土办法的是竖排 `calculate_kinsoku_action`：
  只比 `|新字距 − 基准字距|`，**看不见标点空白**，会把求解器本来吃得下的
  列推出去。现在它对两个候选各解一次 `adjust.solve`，按**词典序**比价——
  从最后手段（字距 `inter_char`）往前逐级比形变量，先分出胜负的那一级说了
  算，全等时选挤进（clreq：先挤进，后推出）。后端只剩组装 gap 与落盘。

  > 比价一度写成「按优先顺序序号加权的平均形变」，是**错的**：clreq 的
  > 优先顺序是词典序（第 1 级用尽才轮到第 2 级），把逗号空白收满 0.5 em
  > 在规范语义里是零代价的正常操作，加权和却把它算成「形变 0.5 的昂贵
  > 操作」——量级差远大于权重差（5 vs 8）。随机扫描 4000 组列，约 13% 的
  > 决策被翻转，方向一律是「字距零形变的挤进」输给「字距全动的推出」。
  > 单测 `resolve_overflow: 收标点空白不算代价，字距零形变必胜` 钉住了这
  > 一类。注意这类错误**回归测试抓不到**：输出仍然「看着合理」，是规范
  > 符合性偏差而非视觉 bug。
- ~~`punct_squeeze.plan` 一次只判一个字符，可能需要 `plan_run`~~ →
  **不需要，改成一条契约**：调用点（`annotate_context_squeeze`）本来就是
  逐字循环，`plan_run` 只是把循环搬进共享层，不消除任何重复逻辑，还会把
  脚注标号组透明化这类竖排专有处理带进去。真正缺的是**顺序契约**：
  flatten 阶段写下的 `ATTR_PUNCT_SQUEEZE` 是「不含行首行尾上下文」的初值，
  列首/列末的额外收回由 flatten 预先算成 `ATTR_PUNCT_TRIM_START/END`，
  flush_buffer 断列后按位置取用——两处属性读取，谈不上繁琐。
- ~~**验收工具本身有个洞**~~ → **已修（#137）**：`test/clreq_test.py`
  解析器现跟踪 q/Q 栈与 cm 级联，缩放字形（脚注标号组）坐标与有效字号
  读取正确，并有专门断言守护。第 1 步「只读接线」的对比可放心用它。
- ~~叹问号叠加未识别为刚性两字幅单元~~ → **已补（#139，P2 前置）**：
  `is_stacked_pair` / `is_unbreakable_pair` 放行 `？！` `！？`，
  `kinsoku.no_break_between` 判序在行首禁则之前返回 `unbreakable_pair`。
  本设计 §2.2 的刚性单元判定直接复用；注意横排的教训——叠加对是点号、
  字面自带可挤空白，刚性单元内部 **shrink 也要清零**。
