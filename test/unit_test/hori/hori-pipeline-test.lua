-- Unit tests for hori.luatex-cn-hori-pipeline (mocked node lists)
local test_utils = require("test.test_utils")
local pipeline = require("hori.luatex-cn-hori-pipeline")
local spacing = require("hori.luatex-cn-hori-spacing")

local GLYPH = node.id("glyph")
local GLUE = node.id("glue")
local PENALTY = node.id("penalty")
local KERN = node.id("kern")

local EM = 655360  -- mock font.getfont().size

local function glyph(char)
    return test_utils.make_direct_node(GLYPH, { char = char, font = 0 })
end

-- Collect {id=..., ...} descriptors of a direct list for easy assertions
local function describe(head)
    local out = {}
    local n = head
    while n do
        local d = { id = n.id }
        if n.id == GLYPH then d.char = n.char end
        if n.id == GLUE then
            d.width, d.stretch, d.shrink = n.width, n.stretch, n.shrink
            d.class = node.direct.get_attribute(n, pipeline.ATTR_ADJUST_CLASS)
        end
        if n.id == PENALTY then d.penalty = n.penalty end
        out[#out + 1] = d
        n = n.next
    end
    return out
end

-- Reset options before each scenario
local function run(nodes, setup)
    pipeline.setup({ style = "mainland", level = "basic",
                     cjk_latin_space = true, inter_cjk_stretch = 0.05,
                     quote_style = "keep", hanging_punct = false })
    if setup then pipeline.setup(setup) end
    local head = test_utils.link_nodes(nodes)
    return describe(pipeline.process(head))
end

-- ============================================================================

test_utils.run_test("cjk-cjk: glue inserted between hanzi", function()
    local seq = run({ glyph(0x4E00), glyph(0x4E8C) })  -- 一二
    test_utils.assert_eq(#seq, 3)
    test_utils.assert_eq(seq[1].char, 0x4E00)
    test_utils.assert_eq(seq[2].id, GLUE)
    test_utils.assert_eq(seq[2].width, 0)
    test_utils.assert_eq(seq[2].stretch, math.floor(0.05 * EM + 0.5))
    test_utils.assert_eq(seq[2].class, spacing.ADJUST_CLASS_CODES.fallback)
    test_utils.assert_eq(seq[3].char, 0x4E8C)
end)

test_utils.run_test("kinsoku: penalty precedes the glue before 。", function()
    local seq = run({ glyph(0x4E00), glyph(0x3002) })  -- 一。
    test_utils.assert_eq(#seq, 4)
    test_utils.assert_eq(seq[2].id, PENALTY)
    test_utils.assert_eq(seq[2].penalty, 10000)
    test_utils.assert_eq(seq[3].id, GLUE)
end)

test_utils.run_test("cjk-latin: quarter-em glue with adjust attribute", function()
    local seq = run({ glyph(0x4E00), glyph(0x61) })  -- 一a
    test_utils.assert_eq(#seq, 3)
    test_utils.assert_eq(seq[2].id, GLUE)
    test_utils.assert_eq(seq[2].width, math.floor(0.25 * EM + 0.5))
    test_utils.assert_eq(seq[2].shrink, math.floor(0.125 * EM + 0.5))
    test_utils.assert_eq(seq[2].stretch, math.floor(0.25 * EM + 0.5))
    test_utils.assert_eq(seq[2].class, spacing.ADJUST_CLASS_CODES.cjk_western)
end)

test_utils.run_test("latin-latin: nothing inserted", function()
    local seq = run({ glyph(0x61), glyph(0x62), glyph(0x63) })  -- abc
    test_utils.assert_eq(#seq, 3)
    for _, d in ipairs(seq) do
        test_utils.assert_eq(d.id, GLYPH)
    end
end)

test_utils.run_test("existing glue blocks insertion (source space wins)", function()
    -- 一 [existing space glue] a : clreq 允许用西文词间空格替代中西间距
    local sp = test_utils.make_direct_node(GLUE, { width = 100000, stretch = 0, shrink = 0 })
    local seq = run({ glyph(0x4E00), sp, glyph(0x61) })
    test_utils.assert_eq(#seq, 3)  -- nothing added
    test_utils.assert_eq(seq[2].width, 100000)
end)

test_utils.run_test("font kern is transparent for the boundary", function()
    local k = test_utils.make_direct_node(KERN, { kern = 500 })
    local seq = run({ glyph(0x4E00), k, glyph(0x4E8C) })
    -- glue inserted after the kern, before the second glyph
    test_utils.assert_eq(#seq, 4)
    test_utils.assert_eq(seq[2].id, KERN)
    test_utils.assert_eq(seq[3].id, GLUE)
    test_utils.assert_eq(seq[4].char, 0x4E8C)
end)

test_utils.run_test("kinsoku level option is honored", function()
    local seq = run({ glyph(0x4E00), glyph(0x2014) }, { level = "strict" })  -- 一—
    test_utils.assert_eq(seq[2].id, PENALTY)
    local seq_basic = run({ glyph(0x4E00), glyph(0x2014) })
    test_utils.assert_eq(seq_basic[2].id, GLUE)  -- no penalty at basic
end)

test_utils.run_test("cjk-latin-space=false falls back to bare break point", function()
    local seq = run({ glyph(0x4E00), glyph(0x61) }, { cjk_latin_space = false })
    test_utils.assert_eq(seq[2].id, GLUE)
    test_utils.assert_eq(seq[2].width, 0)
end)

test_utils.run_test("quote conversion is opt-in: default keep leaves quotes alone", function()
    local seq = run({ glyph(0x300C), glyph(0x4E00) })  -- 「一
    test_utils.assert_eq(seq[1].char, 0x300C)
end)

test_utils.run_test("quote-style=curly converts corner quotes (clreq 引号体例)", function()
    local seq = run({ glyph(0x300C), glyph(0x4E00), glyph(0x300D) },
                    { quote_style = "curly" })
    test_utils.assert_eq(seq[1].char, 0x201C)          -- 「→“
    test_utils.assert_eq(seq[#seq].char, 0x201D)       -- 」→”
    -- 转换后的字符参与禁则：行尾禁断在“ 之后
    -- （“ 属 open 类，boundary 应带 penalty）
    local found_penalty = false
    for _, d in ipairs(seq) do
        if d.penalty == 10000 then found_penalty = true end
    end
    test_utils.assert_true(found_penalty)
end)

test_utils.run_test("quote-style=auto follows style; corner for taiwan", function()
    local seq = run({ glyph(0x201C), glyph(0x4E00) },
                    { style = "taiwan", quote_style = "auto" })
    test_utils.assert_eq(seq[1].char, 0x300C)          -- “→「
end)

test_utils.run_test("head is preserved", function()
    local g1, g2 = glyph(0x4E00), glyph(0x4E8C)
    test_utils.link_nodes({ g1, g2 })
    local head = pipeline.process(g1)
    test_utils.assert_eq(head, g1)
end)

print("All hori-pipeline tests passed.")
