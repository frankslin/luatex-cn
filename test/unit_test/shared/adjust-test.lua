-- Unit tests for shared.luatex-cn-adjust
-- Covers every clreq compression (7 steps) and expansion (2 steps + fallback)
-- priority branch. Each test cites the clreq clause it verifies.
local test_utils = require("test.test_utils")
local adjust = require("shared.luatex-cn-adjust")

local function solve(target, gaps) return adjust.solve(target, gaps) end

-- Convenience gap builders
local function shrinkable(width, min, class)
    return { width = width, min = min, shrink_class = class }
end
local function stretchable(width, max, class)
    return { width = width, max = max, stretch_class = class }
end
local function fallback_gap(width)
    return { width = width, fallback = true }
end

-- ============================================================================
-- Order constants
-- ============================================================================

test_utils.run_test("SHRINK_ORDER is the clreq 7-step sequence", function()
    local expect = { "line_end_punct", "western_word", "interpunct",
        "bracket", "comma_group", "cjk_western", "fullstop_group" }
    test_utils.assert_eq(#adjust.SHRINK_ORDER, 7)
    for i, name in ipairs(expect) do
        test_utils.assert_eq(adjust.SHRINK_ORDER[i], name)
    end
end)

test_utils.run_test("STRETCH_ORDER is the clreq 2-step sequence", function()
    test_utils.assert_eq(#adjust.STRETCH_ORDER, 2)
    test_utils.assert_eq(adjust.STRETCH_ORDER[1], "western_word")
    test_utils.assert_eq(adjust.STRETCH_ORDER[2], "cjk_western")
end)

-- ============================================================================
-- Basic behavior
-- ============================================================================

test_utils.run_test("exact fit: no changes", function()
    local r = solve(2.0, { shrinkable(1.0, 0.5, "comma_group"),
                           shrinkable(1.0, 0.5, "fullstop_group") })
    test_utils.assert_true(r.achieved)
    test_utils.assert_eq(r.widths[1], 1.0)
    test_utils.assert_eq(r.widths[2], 1.0)
    test_utils.assert_eq(r.deficit, 0)
end)

test_utils.run_test("input gaps are not mutated (pure function)", function()
    local g = shrinkable(1.0, 0.5, "comma_group")
    solve(0.6, { g })
    test_utils.assert_eq(g.width, 1.0)
    test_utils.assert_eq(g.min, 0.5)
end)

-- ============================================================================
-- Compression: strict class ordering (clreq 挤压处理的优先顺序)
-- ============================================================================

test_utils.run_test("shrink: earlier class exhausted before later touched", function()
    -- Step 2 (western_word) must fully absorb before step 5 (comma_group)
    local r = solve(1.3, {
        shrinkable(0.5, 0.25, "western_word"),  -- can give 0.25
        shrinkable(1.0, 0.5, "comma_group"),    -- can give 0.5
    })
    -- Need 0.2 < 0.25 → comes entirely from western_word
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.3, 1e-6)
    test_utils.assert_eq(r.widths[2], 1.0)
end)

test_utils.run_test("shrink: overflow cascades to the next class", function()
    local r = solve(1.1, {
        shrinkable(0.5, 0.25, "western_word"),  -- gives all 0.25
        shrinkable(1.0, 0.5, "comma_group"),    -- gives remaining 0.15
    })
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.25, 1e-6)
    test_utils.assert_near(r.widths[2], 0.85, 1e-6)
end)

test_utils.run_test("shrink: all seven classes in one line", function()
    -- One gap per class, each with 0.1 headroom; need 0.65 total
    -- → first six classes fully drained (0.6), seventh gives 0.05
    local gaps = {}
    for _, class in ipairs(adjust.SHRINK_ORDER) do
        gaps[#gaps + 1] = shrinkable(0.5, 0.4, class)
    end
    local r = solve(3.5 - 0.65, gaps)
    test_utils.assert_true(r.achieved)
    for i = 1, 6 do
        test_utils.assert_near(r.widths[i], 0.4, 1e-6,
            "class " .. adjust.SHRINK_ORDER[i] .. " should be drained")
    end
    test_utils.assert_near(r.widths[7], 0.45, 1e-6,
        "fullstop_group should give only the remainder")
end)

test_utils.run_test("shrink: line_end_punct is the first class", function()
    -- clreq step 1: 位于行末的标点。调成固定的半个汉字宽。
    local r = solve(1.4, {
        shrinkable(1.0, 0.5, "line_end_punct"),
        shrinkable(1.0, 0.5, "fullstop_group"),
    })
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.5, 1e-6)  -- drained first
    test_utils.assert_near(r.widths[2], 0.9, 1e-6)
end)

-- ============================================================================
-- Compression: equal amounts within a class (clreq: 同时、同等量处理)
-- ============================================================================

test_utils.run_test("shrink: equal amount across gaps of one class", function()
    local r = solve(2.7, {
        shrinkable(1.0, 0.5, "comma_group"),
        shrinkable(1.0, 0.5, "comma_group"),
        shrinkable(1.0, 0.5, "comma_group"),
    })
    -- Need 0.3 over 3 gaps → 0.1 each
    test_utils.assert_true(r.achieved)
    for i = 1, 3 do
        test_utils.assert_near(r.widths[i], 0.9, 1e-6)
    end
end)

test_utils.run_test("shrink: saturated gap exits, others continue equally", function()
    local r = solve(2.0, {
        shrinkable(1.0, 0.9, "comma_group"),   -- only 0.1 headroom
        shrinkable(1.0, 0.5, "comma_group"),
        shrinkable(1.0, 0.5, "comma_group"),
    })
    -- Need 1.0: first drops 0.1 then saturates; the other two split the
    -- remaining 0.9 equally → 0.45 each
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.9, 1e-6)
    test_utils.assert_near(r.widths[2], 0.55, 1e-6)
    test_utils.assert_near(r.widths[3], 0.55, 1e-6)
end)

test_utils.run_test("shrink: unachievable reports positive deficit", function()
    local r = solve(0.9, { shrinkable(1.0, 0.5, "comma_group"),
                           { width = 0.5 } })  -- second gap rigid
    -- Available shrink 0.5 but need 0.6
    test_utils.assert_false(r.achieved)
    test_utils.assert_near(r.deficit, 0.1, 1e-6)
    test_utils.assert_near(r.widths[1], 0.5, 1e-6)
    test_utils.assert_eq(r.widths[2], 0.5)
end)

test_utils.run_test("shrink: gaps without shrink_class never shrink", function()
    -- clreq: 一些排版风格中中西间距固定…不允许被挤压 → 编码为无 shrink_class
    local r = solve(1.2, { { width = 0.25, min = 0.125 },  -- no class: rigid
                           shrinkable(1.0, 0.5, "fullstop_group") })
    test_utils.assert_true(r.achieved)
    test_utils.assert_eq(r.widths[1], 0.25)
    test_utils.assert_near(r.widths[2], 0.95, 1e-6)
end)

-- ============================================================================
-- Expansion (clreq 拉伸处理的优先顺序 + 兜底均分)
-- ============================================================================

test_utils.run_test("stretch: western_word before cjk_western", function()
    -- clreq: 西文词距最大拉伸到半个汉字宽
    local r = solve(1.0, {
        stretchable(0.25, 0.5, "western_word"),
        stretchable(0.25, 0.5, "cjk_western"),
        { width = 0.4 },
    })
    -- Need 0.1 → all from western_word
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.35, 1e-6)
    test_utils.assert_eq(r.widths[2], 0.25)
end)

test_utils.run_test("stretch: cascades to cjk_western at cap", function()
    -- clreq: 中西间距从默认宽度开始拉伸，最大可拉大到半个汉字字宽
    local r = solve(1.4, {
        stretchable(0.25, 0.5, "western_word"),
        stretchable(0.25, 0.5, "cjk_western"),
        { width = 0.4 },
    })
    -- Need 0.5: western_word gives 0.25 (to cap), cjk gives 0.25
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.5, 1e-6)
    test_utils.assert_near(r.widths[2], 0.5, 1e-6)
end)

test_utils.run_test("stretch: fallback distributes evenly over hanzi gaps", function()
    -- clreq: 最后没有拉伸机会再按平均拉大字距的方式处理
    local r = solve(1.0, {
        stretchable(0.25, 0.5, "western_word"),
        fallback_gap(0), fallback_gap(0), fallback_gap(0), fallback_gap(0),
    })
    -- Need 0.75: western_word gives 0.25, remaining 0.5 → 0.125 each
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.5, 1e-6)
    for i = 2, 5 do
        test_utils.assert_near(r.widths[i], 0.125, 1e-6)
    end
end)

test_utils.run_test("stretch: no fallback gaps reports negative deficit", function()
    local r = solve(1.0, { stretchable(0.25, 0.5, "western_word") })
    test_utils.assert_false(r.achieved)
    test_utils.assert_near(r.deficit, -0.5, 1e-6)
    test_utils.assert_near(r.widths[1], 0.5, 1e-6)
end)

test_utils.run_test("stretch: equal amount within a class, saturation exits", function()
    local r = solve(1.55, {
        stretchable(0.25, 0.3, "western_word"),   -- headroom 0.05
        stretchable(0.25, 0.5, "western_word"),   -- headroom 0.25
        { width = 0.8 },
    })
    -- Need 0.25: equal split 0.125 each, but first caps at +0.05;
    -- second takes the remaining 0.2
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.3, 1e-6)
    test_utils.assert_near(r.widths[2], 0.45, 1e-6)
end)

-- ============================================================================
-- Mixed / integration
-- ============================================================================

test_utils.run_test("integration: sp-scale units work identically", function()
    -- The solver is unit-agnostic: same scenario in sp (1em = 655360)
    local em = 655360
    local r = solve(2.7 * em, {
        shrinkable(1.0 * em, 0.5 * em, "comma_group"),
        shrinkable(1.0 * em, 0.5 * em, "comma_group"),
        shrinkable(1.0 * em, 0.5 * em, "comma_group"),
    })
    test_utils.assert_true(r.achieved)
    for i = 1, 3 do
        test_utils.assert_near(r.widths[i], 0.9 * em, 1)
    end
end)

test_utils.run_test("integration: drain order across line_end + word + comma", function()
    local r = solve(2.45, {
        shrinkable(0.5, 0.0, "line_end_punct"),   -- headroom 0.5
        shrinkable(0.25, 0.125, "western_word"),  -- headroom 0.125
        shrinkable(0.5, 0.0, "comma_group"),      -- headroom 0.5
        { width = 2.0 },
    })
    -- natural 3.25, need 0.8: line_end gives 0.5, western 0.125,
    -- comma gives remaining 0.175
    test_utils.assert_true(r.achieved)
    test_utils.assert_near(r.widths[1], 0.0, 1e-6)
    test_utils.assert_near(r.widths[2], 0.125, 1e-6)
    test_utils.assert_near(r.widths[3], 0.325, 1e-6)
    test_utils.assert_eq(r.widths[4], 2.0)
end)

print("All adjust tests passed.")
