-- Unit tests for hori.luatex-cn-hori-adjust-line (H2 pure planning half)
-- Every case cites the clreq rule it verifies.
local test_utils = require("test.test_utils")
local adjline = require("hori.luatex-cn-hori-adjust-line")

local EM = 655360
local function em(x) return math.floor(x * EM + 0.5) end

-- ============================================================================
-- plan(): priority redistribution (clreq 挤压 7 级 / 拉伸 2 级 + 兜底均分)
-- ============================================================================

test_utils.run_test("plan: nothing to do returns nil", function()
    test_utils.assert_nil(adjline.plan({}, nil, {}))
end)

test_utils.run_test("plan: shrink priority — western word space empties before comma group", function()
    -- clreq 挤压顺序: 西文词距(2) 先于 逗顿分(5)。TeX 曾按比例同时挤两者；
    -- 二次分配应先把词距挤到下限，再动标点空白。
    local gaps = {
        { width = em(0.25), stretch = em(0.25), shrink = em(0.125),
          class = "western_word", effective = em(0.15) },   -- TeX 挤了 0.10
        { width = 0, stretch = 0, shrink = em(0.5),
          class = "comma_group", effective = -em(0.10) },   -- TeX 挤了 0.10
    }
    -- target = 0.15 + (-0.10) = 0.05 em；总缺口 0.20 em
    local r = adjline.plan(gaps, nil, { line_end_punct = "compress" })
    -- 词距先挤满 0.125 em（到下限 0.125），剩余 0.075 em 由逗号空白承担
    test_utils.assert_eq(r.widths[1], em(0.125))
    test_utils.assert_eq(r.widths[2], em(0.05) - em(0.125))
    test_utils.assert_eq(r.line_end_kern, 0)
end)

test_utils.run_test("plan: stretch priority — western word before cjk_western, fallback last", function()
    -- clreq 拉伸顺序: 西文词距(1) → 中西间距(2) → 兜底均分
    local gaps = {
        { width = em(0.25), stretch = em(0.25), shrink = 0,
          class = "western_word", effective = em(0.35) },
        { width = em(0.25), stretch = em(0.25), shrink = 0,
          class = "cjk_western", effective = em(0.35) },
        { width = 0, stretch = em(0.05), shrink = 0,
          class = "fallback", effective = em(0.10) },
    }
    -- target = 0.80 em，自然和 0.50 em，需拉伸 0.30 em：
    -- 词距先拉满 +0.25，剩 0.05 给中西间距，兜底不动
    local r = adjline.plan(gaps, nil, {})
    test_utils.assert_eq(r.widths[1], em(0.5))
    test_utils.assert_eq(r.widths[2], em(0.30))
    test_utils.assert_eq(r.widths[3], 0)
end)

test_utils.run_test("plan: deficit keeps best-effort mins (no un-shrink via rounding)", function()
    local gaps = {
        { width = em(0.25), stretch = 0, shrink = em(0.125),
          class = "western_word", effective = 0 },  -- TeX 声称挤到 0（超容量）
    }
    -- target 0，但下限 0.125 em：解不可达，宽度须停在下限而非被舍入差额抬回
    local r = adjline.plan(gaps, nil, {})
    test_utils.assert_eq(r.widths[1], em(0.125))
end)

-- ============================================================================
-- plan(): 行末标点（clreq 挤压第 1 级 / 行末标点固定半字宽）
-- ============================================================================

test_utils.run_test("plan compress: full blank reclaimed, fallback absorbs", function()
    local gaps = {
        { width = 0, stretch = em(0.05), shrink = 0,
          class = "fallback", effective = 0 },
        { width = 0, stretch = em(0.05), shrink = 0,
          class = "fallback", effective = 0 },
    }
    local r = adjline.plan(gaps, { blank = em(0.5) },
        { line_end_punct = "compress" })
    test_utils.assert_eq(r.line_end_kern, -em(0.5))
    -- 兜底均分：0.5 em 平摊到两个 gap
    test_utils.assert_near(r.widths[1], em(0.25), 2)
    test_utils.assert_near(r.widths[1] + r.widths[2], em(0.5), 2)
end)

test_utils.run_test("plan natural: blank shrinks first, exactly by the line's need", function()
    -- 行被 TeX 挤了 0.2 em（逗号空白 effective -0.2）；natural 模式下
    -- 第 1 级（行末标点空白）优先承担全部 0.2，行内逗号空白应复原为 0
    local gaps = {
        { width = 0, stretch = 0, shrink = em(0.5),
          class = "comma_group", effective = -em(0.2) },
    }
    local r = adjline.plan(gaps, { blank = em(0.5) },
        { line_end_punct = "natural" })
    test_utils.assert_near(r.line_end_kern, -em(0.2), 2)
    test_utils.assert_near(r.widths[1], 0, 2)
end)

test_utils.run_test("plan compress falls back to natural when nothing can absorb", function()
    -- 无兜底、无可拉伸 gap：不能凭空压走 0.5 em（会在行尾留洞）
    local gaps = {
        { width = 0, stretch = 0, shrink = em(0.5),
          class = "comma_group", effective = 0 },
    }
    local r = adjline.plan(gaps, { blank = em(0.5) },
        { line_end_punct = "compress" })
    -- 行不紧（effective=width），natural 求解不动任何东西
    test_utils.assert_eq(r.line_end_kern, 0)
    test_utils.assert_eq(r.widths[1], 0)
end)

test_utils.run_test("plan surplus: last-line justify absorbs the parfillskip slack", function()
    -- H5 justify：parfillskip 清零后，其伸展量作为 surplus 交间隙吸收——
    -- 先按拉伸优先级（西文词距→中西间距），余量兜底均分
    local gaps = {
        { width = em(0.25), stretch = em(0.25), shrink = 0,
          class = "western_word", effective = em(0.25) },
        { width = 0, stretch = em(0.05), shrink = 0,
          class = "fallback", effective = 0 },
        { width = 0, stretch = em(0.05), shrink = 0,
          class = "fallback", effective = 0 },
    }
    local r = adjline.plan(gaps, nil, {}, em(1.25))
    -- 词距先拉满 +0.25 → 0.5em；剩 1.0em 兜底均分到两个 fallback
    test_utils.assert_eq(r.widths[1], em(0.5))
    test_utils.assert_near(r.widths[2], em(0.5), 2)
    test_utils.assert_near(r.widths[2] + r.widths[3], em(1.0), 2)
end)

test_utils.run_test("plan: exact sum (rounding remainder lands in last gap)", function()
    local gaps = {}
    for _ = 1, 7 do
        gaps[#gaps + 1] = { width = 0, stretch = em(0.05), shrink = 0,
                            class = "fallback", effective = 0 }
    end
    local blank = em(0.5)
    local r = adjline.plan(gaps, { blank = blank }, {})
    local sum = 0
    for _, w in ipairs(r.widths) do sum = sum + w end
    test_utils.assert_eq(sum, blank)  -- 精确到 sp
end)

-- ============================================================================
-- line_end_blank_em(): 行末字形内可回收空白（按字面分布与风格）
-- ============================================================================

test_utils.run_test("line_end_blank_em: mainland end-blank / taiwan half / none", function()
    test_utils.assert_eq(adjline.line_end_blank_em(0x3002, "mainland"), 0.5)
    test_utils.assert_eq(adjline.line_end_blank_em(0xFF0C, "mainland"), 0.5)
    -- 台式居中：末端空白为两侧的一半
    test_utils.assert_eq(adjline.line_end_blank_em(0x3002, "taiwan"), 0.25)
    test_utils.assert_eq(adjline.line_end_blank_em(0x3002, "none"), 0)
    -- 开括号空白在始端，行末无可回收空白；汉字无空白
    test_utils.assert_eq(adjline.line_end_blank_em(0x300C, "mainland"), 0)
    test_utils.assert_eq(adjline.line_end_blank_em(0x4E00, "mainland"), 0)
    -- 冒号不参与挤压（clreq 优先级表无冒号）
    test_utils.assert_eq(adjline.line_end_blank_em(0xFF1A, "mainland"), 0)
end)

test_utils.run_test("line_end_blank_em: hanging reclaims the whole point advance", function()
    -- 行尾点号悬挂（opt-in）：点号整字悬于版口外
    test_utils.assert_eq(adjline.line_end_blank_em(0x3002, "mainland", true), 1)
    test_utils.assert_eq(adjline.line_end_blank_em(0xFF0C, "mainland", true), 1)
    -- 仅点号悬挂：结束括号仍按半字挤压
    test_utils.assert_eq(adjline.line_end_blank_em(0x300D, "mainland", true), 0.5)
    -- 非标点不受影响；style=none 不悬挂
    test_utils.assert_eq(adjline.line_end_blank_em(0x4E00, "mainland", true), 0)
    test_utils.assert_eq(adjline.line_end_blank_em(0x3002, "none", true), 0)
end)

print("All hori-adjust-line tests passed.")
