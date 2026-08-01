-- Unit tests for hori.luatex-cn-hori-linemark (H3 pure planning / path halves)
local test_utils = require("test.test_utils")
local linemark = require("hori.luatex-cn-hori-linemark")

local EM = 655360
local function em(x) return math.floor(x * EM + 0.5) end

-- Build a glyph item row: marks = array of attr values (or false), each 1 em
local function items(marks, punct_at)
    local out = {}
    for i, m in ipairs(marks) do
        out[#out + 1] = {
            mark = m or nil,
            x0 = (i - 1) * EM, x1 = i * EM, em = EM,
            is_punct = (punct_at and punct_at[i]) or false,
        }
    end
    return out
end

-- mark value = kind + 4*serial
local Z1 = 1 + 4 * 1  -- 专名 run A
local Z2 = 1 + 4 * 2  -- 专名 run B (adjacent, distinct)
local S1 = 2 + 4 * 3  -- 书名甲
local E1 = 3 + 4 * 4  -- 着重

test_utils.run_test("plan_line: unmarked line yields no draws", function()
    local d = linemark.plan_line(items({ false, false, false }))
    test_utils.assert_eq(#d, 0)
end)

test_utils.run_test("plan_line: one underline run spans first to last glyph", function()
    local d = linemark.plan_line(items({ false, Z1, Z1, Z1, false }))
    test_utils.assert_eq(#d, 1)
    test_utils.assert_eq(d[1].type, "underline")
    test_utils.assert_eq(d[1].anchor, 2)
    test_utils.assert_eq(d[1].x0, em(1))
    test_utils.assert_eq(d[1].x1, em(4))
end)

test_utils.run_test("plan_line: adjacent marks shortened at the junction (clreq ≤1/8 em)", function()
    -- 「\专名{汉}\专名{高祖}」: 相邻两条专名号在交界处各缩 1/16 em
    local d = linemark.plan_line(items({ Z1, Z2, Z2 }))
    test_utils.assert_eq(#d, 2)
    test_utils.assert_eq(d[1].x1, em(1) - em(1 / 16))
    test_utils.assert_eq(d[2].x0, em(1) + em(1 / 16))
    -- 非交界端不缩
    test_utils.assert_eq(d[1].x0, 0)
    test_utils.assert_eq(d[2].x1, em(3))
end)

test_utils.run_test("plan_line: wave run for 书名号甲式", function()
    local d = linemark.plan_line(items({ S1, S1 }))
    test_utils.assert_eq(d[1].type, "wave")
end)

test_utils.run_test("plan_line: emphasis dots skip punctuation (clreq 标点上不加着重号)", function()
    local d = linemark.plan_line(items({ E1, E1, E1 }, { [2] = true }))
    test_utils.assert_eq(#d, 1)
    test_utils.assert_eq(d[1].type, "dots")
    test_utils.assert_eq(#d[1].centers, 2)
    test_utils.assert_eq(d[1].centers[1], em(0.5))
    test_utils.assert_eq(d[1].centers[2], em(2.5))
end)

test_utils.run_test("plan_line: interrupted mark forms two runs", function()
    local d = linemark.plan_line(items({ Z1, false, Z1 }))
    test_utils.assert_eq(#d, 2)
    -- 中断（非相邻）不触发交界缩短
    test_utils.assert_eq(d[1].x1, em(1))
    test_utils.assert_eq(d[2].x0, em(2))
end)

-- ============================================================================
-- Path builders (pure string generation, origin-mode pdf literal)
-- ============================================================================

test_utils.run_test("underline_path: stroked line below baseline", function()
    local p = linemark.underline_path(0, em(3), EM)
    test_utils.assert_match(p, "^q .* m .* l S Q$")
    test_utils.assert_match(p, "%-1%.79")  -- 0.18em @ 10pt ≈ -1.79 bp
end)

test_utils.run_test("wave_path: whole periods of C1 bezier quarters", function()
    local p = linemark.wave_path(0, em(2), EM)
    local n = 0
    for _ in p:gmatch(" c") do n = n + 1 end
    -- 2 em / 0.4 em ≈ 5 periods × 4 quarters
    test_utils.assert_eq(n, 20)
    test_utils.assert_match(p, "S Q$")
end)

test_utils.run_test("dots_path: one filled circle per center", function()
    local p = linemark.dots_path({ em(0.5), em(1.5) }, EM)
    local n = 0
    for _ in p:gmatch("c f") do n = n + 1 end
    test_utils.assert_eq(n, 2)
end)

test_utils.run_test("wave_path: zero-length run yields empty path", function()
    test_utils.assert_eq(linemark.wave_path(em(1), em(1), EM), "")
end)

print("All hori-linemark tests passed.")
