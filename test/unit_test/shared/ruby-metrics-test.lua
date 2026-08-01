-- Unit tests for shared.luatex-cn-ruby-metrics (clreq 行间注度量, H4/P4 共享)
local test_utils = require("test.test_utils")
local ruby = require("shared.luatex-cn-ruby-metrics")

-- ============================================================================
-- clreq 常量（横竖排同源，条款注明于模块内）
-- ============================================================================

test_utils.run_test("constants match clreq ratios", function()
    test_utils.assert_eq(ruby.RUBY_SIZE_RATIO, 0.5)      -- 拼音字号一半
    test_utils.assert_near(ruby.ZHUYIN_WIDTH_RATIO, 0.3) -- 注音:汉字 = 3:10
    test_utils.assert_near(ruby.ZHUYIN_LIGHT_TONE_RATIO, 1 / 15) -- 轻声 1:15
    test_utils.assert_eq(ruby.RUBY_MIN_SEP, 0.25)        -- 相邻注文 ≥ 1/4 注文字宽
    test_utils.assert_eq(ruby.ZHUYIN_SIDE_GAP, 0.5)      -- 注音右置预留 ≥ 1/2 字宽
end)

-- ============================================================================
-- layout(): clreq 词对齐
-- ============================================================================

test_utils.run_test("layout: annotation shorter — spread with half-slot edges", function()
    -- 注文短于基文 → 加大注文字距（clreq）；基文密排
    local L = ruby.layout(2000, 1600, 2, 2)
    test_utils.assert_eq(L.width, 2000)
    test_utils.assert_eq(L.base_edge, 0)
    test_utils.assert_eq(L.base_inner, 0)
    -- 差额 400 分 2 槽：内隙 200，两端各 100
    test_utils.assert_near(L.ann_edge, 100, 0.01)
    test_utils.assert_near(L.ann_inner, 200, 0.01)
    -- 复核封闭性: 2·edge + (n−1)·inner = 差额
    test_utils.assert_near(2 * L.ann_edge + 1 * L.ann_inner, 400, 0.01)
end)

test_utils.run_test("layout: annotation longer — base spread instead", function()
    -- 注文长于基文 → 加大基文字距（clreq）
    local L = ruby.layout(1000, 1500, 1, 1)
    test_utils.assert_eq(L.width, 1500)
    test_utils.assert_eq(L.ann_edge, 0)
    -- 单字基文退化为居中：edge = 差额/2
    test_utils.assert_near(L.base_edge, 250, 0.01)
end)

test_utils.run_test("layout: equal widths — everything solid", function()
    local L = ruby.layout(1200, 1200, 2, 3)
    test_utils.assert_eq(L.width, 1200)
    test_utils.assert_eq(L.base_edge, 0)
    test_utils.assert_eq(L.ann_edge, 0)
    test_utils.assert_eq(L.ann_inner, 0)
end)

test_utils.run_test("layout: multi-syllable spread closes exactly", function()
    -- 基文 4 字 vs 注文 3 音节，注文短 900：3 槽各 300
    local L = ruby.layout(4000, 3100, 4, 3)
    test_utils.assert_near(L.ann_inner, 300, 0.01)
    test_utils.assert_near(L.ann_edge, 150, 0.01)
    test_utils.assert_near(2 * L.ann_edge + 2 * L.ann_inner, 900, 0.01)
end)

print("All ruby-metrics tests passed.")
