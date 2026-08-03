-- Unit tests for shared.luatex-cn-kinsoku
-- Each test cites the clreq clause it verifies.
local test_utils = require("test.test_utils")
local kinsoku = require("shared.luatex-cn-kinsoku")

local function nb(prev, next_c, opts)
    return kinsoku.no_break_between(prev, next_c, opts)
end

-- ============================================================================
-- Line start / line end prohibition by level (clreq 行首行尾禁则)
-- ============================================================================

test_utils.run_test("levels: none disables everything", function()
    test_utils.assert_false(nb(0x4E00, 0x3002, { level = "none" }))  -- 一|。
    test_utils.assert_false(nb(0x300C, 0x4E00, { level = "none" }))  -- 「|一
end)

test_utils.run_test("basic: pause marks may not start a line", function()
    local forbidden, reason = nb(0x4E00, 0xFF0C, { level = "basic" })  -- 一|，
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "forbid_start")
end)

test_utils.run_test("basic: connector/interpunct/solidus may not start a line", function()
    -- clreq basic 明确包含连接号、间隔号、分隔号（现行竖排引擎未覆盖）
    for _, c in ipairs({ 0xFF5E, 0x002D, 0x00B7, 0x002F }) do
        test_utils.assert_true(nb(0x4E00, c, { level = "basic" }),
            string.format("U+%04X should not start a line at basic", c))
    end
end)

test_utils.run_test("basic: opening bracket may not end a line", function()
    local forbidden, reason = nb(0x300C, 0x4E00, { level = "basic" })  -- 「|一
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "forbid_end")
end)

test_utils.run_test("gb: solidus additionally may not end a line", function()
    test_utils.assert_false(nb(0x002F, 0x4E00, { level = "basic" }))
    test_utils.assert_true(nb(0x002F, 0x4E00, { level = "gb" }))
end)

test_utils.run_test("strict: dash/ellipsis may not start a line", function()
    test_utils.assert_false(nb(0x4E00, 0x2014, { level = "gb" }))
    test_utils.assert_true(nb(0x4E00, 0x2014, { level = "strict" }))
    test_utils.assert_true(nb(0x4E00, 0x2026, { level = "strict" }))
end)

test_utils.run_test("default level is basic", function()
    test_utils.assert_true(nb(0x4E00, 0x3002))       -- 。 start-forbidden
    test_utils.assert_false(nb(0x4E00, 0x2014))      -- — needs strict
end)

test_utils.run_test("plain hanzi-hanzi break is free", function()
    local forbidden = nb(0x4E00, 0x4E8C, { level = "strict" })  -- 一|二
    test_utils.assert_false(forbidden)
end)

-- ============================================================================
-- Unbreakable two-em units (clreq 符号分离禁则: 两字宽标点视为一体)
-- ============================================================================

test_utils.run_test("dash pair —— is unbreakable", function()
    local forbidden, reason = nb(0x2014, 0x2014, { level = "none" })
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "unbreakable_pair")
end)

test_utils.run_test("ellipsis pairs …… ⋯⋯ are unbreakable", function()
    test_utils.assert_true(nb(0x2026, 0x2026, { level = "none" }))
    test_utils.assert_true(nb(0x22EF, 0x22EF, { level = "none" }))
end)

test_utils.run_test("pair boundary in long runs is breakable", function()
    -- clreq: 若这些标点符号连续出现多个，允许将其拆成两行
    test_utils.assert_false(kinsoku.pair_boundary_breakable(2, 1))  -- 单对内
    test_utils.assert_true(kinsoku.pair_boundary_breakable(4, 2))   -- 对与对之间
    test_utils.assert_false(kinsoku.pair_boundary_breakable(4, 1))  -- 对内
    test_utils.assert_false(kinsoku.pair_boundary_breakable(4, 3))  -- 对内
    test_utils.assert_true(kinsoku.pair_boundary_breakable(6, 4))
end)

-- ============================================================================
-- Numeral rules (clreq 符号分离禁则: 数字及其相应的前后缀单位符号)
-- ============================================================================

test_utils.run_test("digit runs are unbreakable", function()
    local forbidden, reason = nb(0x31, 0x32, { level = "none" })  -- 1|2
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "digit_run")
    -- Fullwidth digits too
    test_utils.assert_true(nb(0xFF11, 0xFF12, { level = "none" }))  -- １|２
end)

test_utils.run_test("digit + unit suffix is unbreakable", function()
    -- clreq: 百分号、千分号、度数符号与其前面的阿拉伯数字之间不能拆
    for _, suffix in ipairs({ 0x25, 0xFF05, 0x2030, 0xB0, 0x2103 }) do
        local forbidden, reason = nb(0x39, suffix, { level = "none" })
        test_utils.assert_true(forbidden,
            string.format("9|U+%04X should be unbreakable", suffix))
        test_utils.assert_eq(reason, "digit_suffix")
    end
    -- But hanzi + % is breakable
    test_utils.assert_false(nb(0x4E00, 0x25, { level = "none" }))
end)

test_utils.run_test("sign prefix + digit is unbreakable", function()
    -- clreq: 正号、负号、正负号与其后面的阿拉伯数字之间不能拆
    for _, sign in ipairs({ 0x2B, 0x2D, 0xB1, 0x2212, 0xFF0B }) do
        local forbidden = nb(sign, 0x35, { level = "none" })
        test_utils.assert_true(forbidden,
            string.format("U+%04X|5 should be unbreakable", sign))
    end
end)

test_utils.run_test("currency + digit is unbreakable (both placements)", function()
    -- clreq: 前置货币符号（如人民币符号¥）和后置货币符号（如越南盾符号₫）
    local forbidden, reason = nb(0xA5, 0x31, { level = "none" })  -- ¥|1
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "currency")
    test_utils.assert_true(nb(0x24, 0x39, { level = "none" }))     -- $|9
    test_utils.assert_true(nb(0xFFE5, 0x31, { level = "none" }))   -- ￥|1
    test_utils.assert_true(nb(0x31, 0x20AB, { level = "none" }))   -- 1|₫
end)

-- ============================================================================
-- Western words (clreq: 混排的西文单词在可使用连字符处之外不得分隔)
-- ============================================================================

test_utils.run_test("letters inside a word are unbreakable", function()
    local forbidden, reason = nb(0x61, 0x62, { level = "none" })  -- a|b
    test_utils.assert_true(forbidden)
    test_utils.assert_eq(reason, "western_word")
end)

test_utils.run_test("break after hyphen is allowed", function()
    -- word-|wrap: hyphen is not a letter, so letter|letter rule not hit;
    -- and hyphen is only start-forbidden as 连接号 at basic (next is letter →
    -- no rule applies at none level)
    test_utils.assert_false(nb(0x2D, 0x61, { level = "none" }))
end)

test_utils.run_test("hanzi-letter boundary is breakable", function()
    test_utils.assert_false(nb(0x4E00, 0x61, { level = "strict" }))
    test_utils.assert_false(nb(0x61, 0x4E00, { level = "strict" }))
end)

-- ============================================================================
-- Backend-facing outputs
-- ============================================================================

test_utils.run_test("penalty_between: 10000 forbidden / 0 free", function()
    test_utils.assert_eq(kinsoku.penalty_between(0x4E00, 0x3002), 10000)
    test_utils.assert_eq(kinsoku.penalty_between(0x4E00, 0x4E8C), 0)
end)

test_utils.run_test("check_wrap: start / end violations", function()
    -- Column full after 一, next is 。→ start violation
    test_utils.assert_eq(kinsoku.check_wrap(0x4E00, 0x3002), "start_violation")
    -- Column would end with 「 → end violation
    test_utils.assert_eq(kinsoku.check_wrap(0x300C, 0x4E00), "end_violation")
    -- No violation
    test_utils.assert_nil(kinsoku.check_wrap(0x4E00, 0x4E8C))
    -- Level none: nothing violates
    test_utils.assert_nil(kinsoku.check_wrap(0x4E00, 0x3002, { level = "none" }))
end)

test_utils.run_test("stacked ？！ reports unbreakable_pair, not forbid_start", function()
    -- ？！ 两符号都是行首禁则字符；若先查禁则会把原因报成 forbid_start，
    -- 下游（hori-spacing 的 RIGID_REASONS）就不会把对内间隙做成刚性。
    for _, pair in ipairs({ { 0xFF1F, 0xFF1F }, { 0xFF01, 0xFF01 },
                            { 0xFF1F, 0xFF01 }, { 0xFF01, 0xFF1F } }) do
        local forbidden, reason = nb(pair[1], pair[2], { level = "basic" })
        test_utils.assert_true(forbidden)
        test_utils.assert_eq(reason, "unbreakable_pair")
    end
    -- 与禁则级别无关（分离禁则独立于四级）
    test_utils.assert_true(nb(0xFF1F, 0xFF01, { level = "none" }))
    -- 汉字＋叹问号仍是普通行首禁则
    local _, reason = nb(0x4E00, 0xFF1F, { level = "basic" })
    test_utils.assert_eq(reason, "forbid_start")
end)

-- ============================================================================
-- 挤进 / 推出决策（clreq 禁则的解决方式）
-- ============================================================================

-- 造一组「N 个字距」的候选：cells 已经从 target 里扣掉，这里只给 gap
local function gaps_of(n, width, opts)
    local t = {}
    for _ = 1, n do
        t[#t + 1] = { width = width, min = 0, max = width,
                      shrink_class = opts and opts.class or "inter_char",
                      fallback = opts == nil or opts.fallback ~= false }
    end
    return t
end

test_utils.run_test("resolve_overflow: 装不下就推出", function()
    -- 挤进候选的 gap 全部压到 0 也超长 → 不可行
    local action = kinsoku.resolve_overflow({
        squeeze = { target = -5, gaps = gaps_of(4, 1) },
        stretch = { target = 3, gaps = gaps_of(2, 1) },
    })
    test_utils.assert_eq(action, "stretch")
end)

test_utils.run_test("resolve_overflow: 形变小的一方胜出", function()
    -- 挤进：4 个 1.0 的字距压成 0.9（形变 0.1）
    -- 推出：2 个 1.0 的字距拉到 2.0（形变 1.0）
    local action, d = kinsoku.resolve_overflow({
        squeeze = { target = 3.6, gaps = gaps_of(4, 1) },
        stretch = { target = 4.0, gaps = gaps_of(2, 1) },
    })
    test_utils.assert_eq(action, "squeeze")
    test_utils.assert_true(d.squeeze_cost < d.stretch_cost)
end)

test_utils.run_test("resolve_overflow: 收标点空白比压字距便宜", function()
    -- 同样要吞掉 0.5：挤进候选靠一个逗号空白（clreq 挤压第 5 级），
    -- 推出候选靠字距（第 8 级，最后手段）。逗号那边应当胜出。
    local squeeze = gaps_of(3, 1)
    squeeze[#squeeze + 1] = { width = 0.5, min = 0, max = 0.5,
                              shrink_class = "comma_group" }
    local action, d = kinsoku.resolve_overflow({
        squeeze = { target = 3.0, gaps = squeeze },   -- 收掉整个逗号空白
        stretch = { target = 1.5, gaps = gaps_of(2, 1) },  -- 字距各压 0.25
    })
    test_utils.assert_eq(action, "squeeze")
    test_utils.assert_true(d.squeeze_cost < d.stretch_cost)
end)

test_utils.run_test("resolve_overflow: 代价相等时先挤进（clreq 先挤进后推出）", function()
    local action = kinsoku.resolve_overflow({
        squeeze = { target = 2, gaps = gaps_of(2, 1) },
        stretch = { target = 2, gaps = gaps_of(2, 1) },
    })
    test_utils.assert_eq(action, "squeeze")
end)

test_utils.run_test("resolve_overflow: 刚性 gap 不参与代价平均", function()
    -- 全刚性的候选没有可比的形变，代价为 0
    local rigid = { { width = 1, min = 1, max = 1 }, { width = 1, min = 1, max = 1 } }
    local action, d = kinsoku.resolve_overflow({
        squeeze = { target = 2, gaps = rigid },
        stretch = { target = 1, gaps = gaps_of(2, 1) },
    })
    test_utils.assert_eq(d.squeeze_cost, 0)
    test_utils.assert_eq(action, "squeeze")
end)

print("All kinsoku tests passed.")
