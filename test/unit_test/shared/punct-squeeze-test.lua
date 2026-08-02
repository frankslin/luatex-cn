-- Unit tests for shared.luatex-cn-punct-squeeze
-- clreq 《标点符号的宽度调整》上下文判定：只在①相邻标点②行首/行尾收回
-- 字面空白，夹在汉字之间的单个标点占满一字幅。每条测试注明 clreq 条款。
local test_utils = require("test.test_utils")
local sq = require("shared.luatex-cn-punct-squeeze")

local HANZI = 0x5B57   -- 字
local COMMA = 0xFF0C   -- ，
local DUNHAO = 0x3001  -- 、
local FULLSTOP = 0x3002 -- 。
local OPEN = 0x300C    -- 「
local CLOSE = 0x300D    -- 」
local QUESTION = 0xFF1F -- ？

local V = { style = "mainland", mode = "vertical" }
local function opts(extra)
    local o = {}
    for k, v in pairs(V) do o[k] = v end
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end
local function approx(a, b)
    test_utils.assert_true(math.abs(a - b) < 1e-9,
        string.format("expected %.6f, got %.6f", b, a))
end

-- ============================================================================
-- 字面空白（clreq: 标点符号的宽度调整——全角字幅内的空白位置）
-- ============================================================================

test_utils.run_test("大陆式点号空白在末端，夹注符号在贴合侧", function()
    local h, t = sq.blanks(COMMA, V)
    approx(h, 0); approx(t, 0.5)
    h, t = sq.blanks(OPEN, V)
    approx(h, 0.5); approx(t, 0)
    h, t = sq.blanks(CLOSE, V)
    approx(h, 0); approx(t, 0.5)
end)

test_utils.run_test("台湾式点号居中：两端各半", function()
    local h, t = sq.blanks(COMMA, opts({ style = "taiwan" }))
    approx(h, 0.25); approx(t, 0.25)
end)

test_utils.run_test("style=none（不调整预设）无任何可收回空白", function()
    local h, t = sq.blanks(COMMA, opts({ style = "none" }))
    approx(h, 0); approx(t, 0)
end)

test_utils.run_test("clreq 直排冒号/分号/问号/叹号固定一字宽", function()
    local h, t = sq.blanks(QUESTION, V)
    approx(h, 0); approx(t, 0)
    local p = sq.plan(HANZI, QUESTION, OPEN, nil, V)
    approx(p.total, 0)
end)

-- ============================================================================
-- ① 上下文：夹在汉字之间不挤压（本次改动的核心）
-- ============================================================================

test_utils.run_test("clreq: 汉字之间的单个标点占满一字幅，不挤压", function()
    for _, c in ipairs({ COMMA, DUNHAO, FULLSTOP, OPEN, CLOSE }) do
        local p = sq.plan(HANZI, c, HANZI, nil, V)
        approx(p.total, 0)
    end
end)

test_utils.run_test("无上下文（prev/next 均缺）也不挤压", function()
    local p = sq.plan(nil, COMMA, nil, nil, V)
    approx(p.total, 0)
end)

-- ============================================================================
-- ② 相邻标点：2 → 1.5 字宽（clreq 连续标点符号的调整）
-- ============================================================================

test_utils.run_test("clreq: 点号 + 夹注符号连排合计 1.5 字宽", function()
    local a = sq.plan(HANZI, COMMA, OPEN, nil, V)   -- ，「
    local b = sq.plan(COMMA, OPEN, HANZI, nil, V)
    approx(a.tail, 0.25)
    approx(b.head, 0.25)
    approx(2 - a.total - b.total, 1.5)
    test_utils.assert_eq(a.reasons[1], "adjacent")
end)

test_utils.run_test("clreq: 夹注符号重复出现（」「）同样缩到 1.5", function()
    local a = sq.plan(HANZI, CLOSE, OPEN, nil, V)
    local b = sq.plan(CLOSE, OPEN, HANZI, nil, V)
    approx(2 - a.total - b.total, 1.5)
end)

test_utils.run_test("adjacent-punct=1：风格可进一步缩到 1 字宽", function()
    local o = opts({ adjacent_punct = "1" })
    local a = sq.plan(HANZI, COMMA, OPEN, nil, o)
    local b = sq.plan(COMMA, OPEN, HANZI, nil, o)
    approx(2 - a.total - b.total, 1.0)
end)

test_utils.run_test("adjacent-punct=natural：不做无条件缩减", function()
    local o = opts({ adjacent_punct = "natural" })
    local a = sq.plan(HANZI, COMMA, OPEN, nil, o)
    approx(a.total, 0)
end)

test_utils.run_test("无夹注符号参与的连排（。、）不触发无条件缩减", function()
    local a = sq.plan(HANZI, FULLSTOP, DUNHAO, nil, V)
    approx(a.total, 0)
end)

-- ============================================================================
-- ③ 行首 / 行尾（clreq 行首行尾的标点宽度调整）
-- ============================================================================

test_utils.run_test("clreq: 行首开始夹注符号缩减始侧半字", function()
    local p = sq.plan(nil, OPEN, HANZI, { at_line_start = true }, V)
    approx(p.head, 0.5)
    approx(p.total, 0.5)
    test_utils.assert_eq(p.reasons[#p.reasons], "line_start")
end)

test_utils.run_test("行首汉字后的点号不因行首而缩减", function()
    local p = sq.plan(nil, COMMA, HANZI, { at_line_start = true }, V)
    approx(p.total, 0)
end)

test_utils.run_test("clreq: 行末点号缩减末侧半字", function()
    local p = sq.plan(HANZI, COMMA, nil, { at_line_end = true }, V)
    approx(p.tail, 0.5)
    test_utils.assert_eq(p.reasons[#p.reasons], "line_end")
end)

test_utils.run_test("line-end-punct=natural / line-start-bracket=natural 关闭行末行首缩减", function()
    local p = sq.plan(HANZI, COMMA, nil, { at_line_end = true },
        opts({ line_end_punct = "natural" }))
    approx(p.total, 0)
    p = sq.plan(nil, OPEN, HANZI, { at_line_start = true },
        opts({ line_start_bracket = "natural" }))
    approx(p.total, 0)
end)

test_utils.run_test("行末缩减覆盖相邻缩减的分摊量（取整段空白）", function()
    local p = sq.plan(HANZI, CLOSE, CLOSE, { at_line_end = true }, V)
    approx(p.tail, 0.5)
end)

-- ============================================================================
-- 缩减上限常量
-- ============================================================================

test_utils.run_test("adjacent_reduction_cap 映射", function()
    approx(sq.adjacent_reduction_cap("1.5"), 0.5)
    approx(sq.adjacent_reduction_cap("1"), 1.0)
    approx(sq.adjacent_reduction_cap("natural"), 0)
    approx(sq.adjacent_reduction_cap(nil), 0.5)
end)

test_utils.run_test("is_bracket 只认开/结夹注符号", function()
    test_utils.assert_true(sq.is_bracket(OPEN))
    test_utils.assert_true(sq.is_bracket(CLOSE))
    test_utils.assert_true(not sq.is_bracket(COMMA))
    test_utils.assert_true(not sq.is_bracket(HANZI))
end)
