-- Unit tests for core.luatex-cn-core-punct
local test_utils = require("test.test_utils")
local punct = require("core.luatex-cn-core-punct")

-- ============================================================================
-- classify
-- ============================================================================

test_utils.run_test("classify: opening brackets", function()
    test_utils.assert_eq(punct.classify(0x300C), "open")   -- 「
    test_utils.assert_eq(punct.classify(0x300E), "open")   -- 『
    test_utils.assert_eq(punct.classify(0xFF08), "open")   -- （
    test_utils.assert_eq(punct.classify(0x3008), "open")   -- 〈
    test_utils.assert_eq(punct.classify(0x300A), "open")   -- 《
    test_utils.assert_eq(punct.classify(0x3010), "open")   -- 【
    test_utils.assert_eq(punct.classify(0x201C), "open")   -- "
    test_utils.assert_eq(punct.classify(0x2018), "open")   -- '
end)

test_utils.run_test("classify: vertical presentation forms (open)", function()
    test_utils.assert_eq(punct.classify(0xFE41), "open")   -- ﹁
    test_utils.assert_eq(punct.classify(0xFE43), "open")   -- ﹃
    test_utils.assert_eq(punct.classify(0xFE35), "open")   -- ︵
    test_utils.assert_eq(punct.classify(0xFE3D), "open")   -- ︽
end)

test_utils.run_test("classify: closing brackets", function()
    test_utils.assert_eq(punct.classify(0x300D), "close")  -- 」
    test_utils.assert_eq(punct.classify(0x300F), "close")  -- 』
    test_utils.assert_eq(punct.classify(0xFF09), "close")  -- ）
    test_utils.assert_eq(punct.classify(0x3009), "close")  -- 〉
    test_utils.assert_eq(punct.classify(0x300B), "close")  -- 》
    test_utils.assert_eq(punct.classify(0x201D), "close")  -- "
    test_utils.assert_eq(punct.classify(0x2019), "close")  -- '
end)

test_utils.run_test("classify: vertical presentation forms (close)", function()
    test_utils.assert_eq(punct.classify(0xFE42), "close")  -- ﹂
    test_utils.assert_eq(punct.classify(0xFE44), "close")  -- ﹄
    test_utils.assert_eq(punct.classify(0xFE36), "close")  -- ︶
    test_utils.assert_eq(punct.classify(0xFE3C), "close")  -- ︼
end)

test_utils.run_test("classify: fullstop", function()
    test_utils.assert_eq(punct.classify(0x3002), "fullstop") -- 。
    test_utils.assert_eq(punct.classify(0xFF0E), "fullstop") -- ．
end)

test_utils.run_test("classify: comma", function()
    test_utils.assert_eq(punct.classify(0xFF0C), "comma")  -- ，
    test_utils.assert_eq(punct.classify(0x3001), "comma")  -- 、
end)

test_utils.run_test("classify: middle punctuation", function()
    test_utils.assert_eq(punct.classify(0xFF1A), "middle") -- ：
    test_utils.assert_eq(punct.classify(0xFF1B), "middle") -- ；
    test_utils.assert_eq(punct.classify(0xFF01), "middle") -- ！
    test_utils.assert_eq(punct.classify(0xFF1F), "middle") -- ？
end)

test_utils.run_test("classify: nobreak characters", function()
    test_utils.assert_eq(punct.classify(0x2014), "nobreak") -- — em dash
    test_utils.assert_eq(punct.classify(0x2026), "nobreak") -- … ellipsis
end)

test_utils.run_test("classify: vertical forms of dash/ellipsis keep nobreak", function()
    -- Regression guard: before the shared-table derivation, VERT_FORM_MAP
    -- replaced — → ︱ / … → ︙ but the replacement targets were missing from
    -- the class tables, so the pair lost its type (and the gap-closing pass
    -- skipped it, leaving a rounding gap between the two dash halves).
    test_utils.assert_eq(punct.classify(0xFE31), "nobreak") -- ︱ vertical em dash
    test_utils.assert_eq(punct.classify(0xFE19), "nobreak") -- ︙ vertical ellipsis
end)

test_utils.run_test("classify: brackets added by the shared clreq table", function()
    -- New coverage inherited from shared.luatex-cn-punct-table (clreq appendix)
    test_utils.assert_eq(punct.classify(0x3016), "open")   -- 〖
    test_utils.assert_eq(punct.classify(0x3017), "close")  -- 〗
    test_utils.assert_eq(punct.classify(0xFF3B), "open")   -- ［
    test_utils.assert_eq(punct.classify(0xFF3D), "close")  -- ］
    test_utils.assert_eq(punct.classify(0xFF5B), "open")   -- ｛
    test_utils.assert_eq(punct.classify(0xFF5D), "close")  -- ｝
end)

test_utils.run_test("classify: non-punctuation returns nil", function()
    test_utils.assert_nil(punct.classify(0x4E00))  -- 一 (CJK character)
    test_utils.assert_nil(punct.classify(0x0041))  -- A (Latin)
    test_utils.assert_nil(punct.classify(0x0020))  -- space
end)

-- ============================================================================
-- is_line_start_forbidden
-- ============================================================================

test_utils.run_test("is_line_start_forbidden: close/fullstop/comma/middle forbidden", function()
    test_utils.assert_true(punct.is_line_start_forbidden("close"))
    test_utils.assert_true(punct.is_line_start_forbidden("fullstop"))
    test_utils.assert_true(punct.is_line_start_forbidden("comma"))
    test_utils.assert_true(punct.is_line_start_forbidden("middle"))
end)

test_utils.run_test("is_line_start_forbidden: open/nobreak allowed", function()
    test_utils.assert_eq(punct.is_line_start_forbidden("open"), false)
    test_utils.assert_eq(punct.is_line_start_forbidden("nobreak"), false)
end)

test_utils.run_test("is_line_start_forbidden: nil type allowed", function()
    test_utils.assert_eq(punct.is_line_start_forbidden(nil), false)
end)

-- ============================================================================
-- is_line_end_forbidden
-- ============================================================================

test_utils.run_test("is_line_end_forbidden: open forbidden", function()
    test_utils.assert_true(punct.is_line_end_forbidden("open"))
end)

test_utils.run_test("is_line_end_forbidden: close/fullstop/comma/middle allowed", function()
    test_utils.assert_eq(punct.is_line_end_forbidden("close"), false)
    test_utils.assert_eq(punct.is_line_end_forbidden("fullstop"), false)
    test_utils.assert_eq(punct.is_line_end_forbidden("comma"), false)
    test_utils.assert_eq(punct.is_line_end_forbidden("middle"), false)
end)

test_utils.run_test("is_line_end_forbidden: nil type allowed", function()
    test_utils.assert_eq(punct.is_line_end_forbidden(nil), false)
end)

-- ============================================================================
-- type_from_code / code_from_type
-- ============================================================================

test_utils.run_test("type_from_code: valid codes", function()
    test_utils.assert_eq(punct.type_from_code(1), "open")
    test_utils.assert_eq(punct.type_from_code(2), "close")
    test_utils.assert_eq(punct.type_from_code(3), "fullstop")
    test_utils.assert_eq(punct.type_from_code(4), "comma")
    test_utils.assert_eq(punct.type_from_code(5), "middle")
    test_utils.assert_eq(punct.type_from_code(6), "nobreak")
end)

test_utils.run_test("type_from_code: invalid code returns nil", function()
    test_utils.assert_nil(punct.type_from_code(0))
    test_utils.assert_nil(punct.type_from_code(7))
    test_utils.assert_nil(punct.type_from_code(99))
end)

test_utils.run_test("code_from_type: valid types", function()
    test_utils.assert_eq(punct.code_from_type("open"), 1)
    test_utils.assert_eq(punct.code_from_type("close"), 2)
    test_utils.assert_eq(punct.code_from_type("fullstop"), 3)
    test_utils.assert_eq(punct.code_from_type("comma"), 4)
    test_utils.assert_eq(punct.code_from_type("middle"), 5)
    test_utils.assert_eq(punct.code_from_type("nobreak"), 6)
end)

test_utils.run_test("code_from_type: invalid type returns nil", function()
    test_utils.assert_nil(punct.code_from_type("unknown"))
    test_utils.assert_nil(punct.code_from_type(""))
end)

test_utils.run_test("type_from_code/code_from_type: roundtrip", function()
    local types = {"open", "close", "fullstop", "comma", "middle", "nobreak"}
    for _, t in ipairs(types) do
        local code = punct.code_from_type(t)
        test_utils.assert_eq(punct.type_from_code(code), t, "roundtrip failed for " .. t)
    end
end)

-- ============================================================================
-- setup
-- ============================================================================

test_utils.run_test("setup: sets global punct config", function()
    _G.punct = nil
    punct.setup({ style = "taiwan", squeeze = false, hanging = true, kinsoku = false })
    test_utils.assert_eq(_G.punct.style, "taiwan")
    test_utils.assert_eq(_G.punct.squeeze, false)
    test_utils.assert_eq(_G.punct.hanging, true)
    test_utils.assert_eq(_G.punct.kinsoku, false)
end)

test_utils.run_test("setup: partial config", function()
    _G.punct = { style = "mainland" }
    punct.setup({ kinsoku = true })
    test_utils.assert_eq(_G.punct.style, "mainland")
    test_utils.assert_eq(_G.punct.kinsoku, true)
end)

-- ============================================================================
-- initialize
-- ============================================================================

test_utils.run_test("initialize: returns context when no judou plugin context", function()
    _G.punct = nil
    local ctx = punct.initialize({}, {}, {})
    test_utils.assert_type(ctx, "table")
    test_utils.assert_eq(ctx.style, "mainland")
    test_utils.assert_eq(ctx.squeeze, true)
    test_utils.assert_eq(ctx.kinsoku, true)
    test_utils.assert_eq(ctx.hanging, false)
end)

test_utils.run_test("initialize: returns nil when judou plugin context has non-normal mode", function()
    local plugin_contexts = { judou = { punct_mode = "judou" } }
    local ctx = punct.initialize({}, {}, plugin_contexts)
    test_utils.assert_nil(ctx)
end)

test_utils.run_test("initialize: reads _G.punct config", function()
    _G.punct = { style = "taiwan", squeeze = false, hanging = true, kinsoku = false }
    local ctx = punct.initialize({}, {}, {})
    test_utils.assert_eq(ctx.style, "taiwan")
    test_utils.assert_eq(ctx.squeeze, false)
    test_utils.assert_eq(ctx.hanging, true)
    test_utils.assert_eq(ctx.kinsoku, false)
    _G.punct = nil
end)

test_utils.run_test("initialize: 宽度调整默认 legacy（R5 分档：古籍类版面不变）", function()
    _G.punct = nil
    local ctx = punct.initialize({}, {}, {})
    test_utils.assert_eq(ctx.squeeze_mode, "legacy")
    test_utils.assert_eq(ctx.adjacent_punct, "1.5")
    test_utils.assert_eq(ctx.line_start_bracket, "trim")
    test_utils.assert_eq(ctx.line_end_punct, "compress")
end)

test_utils.run_test("initialize: squeeze-mode=context 与风格键透传", function()
    _G.punct = nil
    punct.setup({ squeeze_mode = "context", adjacent_punct = "1" })
    local ctx = punct.initialize({}, {}, {})
    test_utils.assert_eq(ctx.squeeze_mode, "context")
    test_utils.assert_eq(ctx.adjacent_punct, "1")
    _G.punct = nil
end)

test_utils.run_test("initialize: style=none 是 clreq 不调整预设（不挤压）", function()
    _G.punct = { style = "none" }
    local ctx = punct.initialize({}, {}, {})
    test_utils.assert_eq(ctx.style, "none")
    test_utils.assert_eq(ctx.squeeze, false)
    _G.punct = nil
end)

-- ============================================================================
-- make_kinsoku_hook
-- ============================================================================

test_utils.run_test("make_kinsoku_hook: returns nil when no ctx", function()
    test_utils.assert_nil(punct.make_kinsoku_hook(nil))
end)

test_utils.run_test("make_kinsoku_hook: returns nil when kinsoku disabled", function()
    test_utils.assert_nil(punct.make_kinsoku_hook({ kinsoku = false }))
end)

test_utils.run_test("make_kinsoku_hook: returns function when kinsoku enabled", function()
    local hook = punct.make_kinsoku_hook({ kinsoku = true })
    test_utils.assert_type(hook, "function")
end)

-- ============================================================================
-- _internal: parse_tounicode (Issue #71)
-- ============================================================================

local parse_tounicode = punct._internal.parse_tounicode

test_utils.run_test("parse_tounicode: valid 4-digit hex string", function()
    test_utils.assert_eq(parse_tounicode("FF0C"), 0xFF0C)
    test_utils.assert_eq(parse_tounicode("3001"), 0x3001)
    test_utils.assert_eq(parse_tounicode("3002"), 0x3002)
    test_utils.assert_eq(parse_tounicode("0041"), 0x0041)
end)

test_utils.run_test("parse_tounicode: nil and empty input", function()
    test_utils.assert_nil(parse_tounicode(nil))
    test_utils.assert_nil(parse_tounicode(""))
end)

test_utils.run_test("parse_tounicode: wrong length strings return nil", function()
    test_utils.assert_nil(parse_tounicode("FF"))       -- too short
    test_utils.assert_nil(parse_tounicode("FF0C00"))   -- too long (surrogate pair)
    test_utils.assert_nil(parse_tounicode("D800DC00")) -- 8-digit surrogate pair
end)

-- ============================================================================
-- _internal: resolve_original_codepoint (Issue #71)
-- ============================================================================

local resolve_original_codepoint = punct._internal.resolve_original_codepoint

test_utils.run_test("resolve_original_codepoint: non-PUA char returns nil", function()
    test_utils.assert_nil(resolve_original_codepoint(99, 0xFF0C))  -- standard Unicode
    test_utils.assert_nil(resolve_original_codepoint(99, 0x4E00))  -- CJK char
    test_utils.assert_nil(resolve_original_codepoint(99, 0x0041))  -- ASCII
end)

test_utils.run_test("resolve_original_codepoint: PUA char with tounicode resolves to punct", function()
    -- Clear cache from previous tests
    for k in pairs(punct._internal.font_tounicode_cache) do
        punct._internal.font_tounicode_cache[k] = nil
    end

    -- Mock font.getfont to return a font with PUA characters
    local orig_getfont = font.getfont
    font.getfont = function(id)
        if id == 42 then
            return {
                size = 655360,
                characters = {
                    [0xF00A0] = { tounicode = "FF0C", index = 100 },  -- ， PUA
                    [0xF0071] = { tounicode = "3001", index = 101 },  -- 、 PUA
                    [0xF0072] = { tounicode = "3002", index = 102 },  -- 。 PUA
                    [0xFF1A]  = { tounicode = "FF1A", index = 200 },  -- ： (not PUA)
                    [0x4E00]  = { index = 300 },                      -- 一 (no tounicode)
                }
            }
        end
        return orig_getfont(id)
    end

    -- PUA chars with punct tounicode should resolve
    test_utils.assert_eq(resolve_original_codepoint(42, 0xF00A0), 0xFF0C)  -- ，
    test_utils.assert_eq(resolve_original_codepoint(42, 0xF0071), 0x3001)  -- 、
    test_utils.assert_eq(resolve_original_codepoint(42, 0xF0072), 0x3002)  -- 。

    -- Non-PUA char should still return nil (even if in same font)
    test_utils.assert_nil(resolve_original_codepoint(42, 0xFF1A))

    -- PUA char not in the font should return nil
    test_utils.assert_nil(resolve_original_codepoint(42, 0xF0099))

    -- Restore
    font.getfont = orig_getfont
end)

test_utils.run_test("resolve_original_codepoint: BMP PUA range also works", function()
    for k in pairs(punct._internal.font_tounicode_cache) do
        punct._internal.font_tounicode_cache[k] = nil
    end

    local orig_getfont = font.getfont
    font.getfont = function(id)
        if id == 43 then
            return {
                size = 655360,
                characters = {
                    [0xE000] = { tounicode = "FF0C", index = 50 },  -- BMP PUA
                }
            }
        end
        return orig_getfont(id)
    end

    test_utils.assert_eq(resolve_original_codepoint(43, 0xE000), 0xFF0C)

    font.getfont = orig_getfont
end)

test_utils.run_test("resolve_original_codepoint: PUA char with non-punct tounicode returns nil", function()
    for k in pairs(punct._internal.font_tounicode_cache) do
        punct._internal.font_tounicode_cache[k] = nil
    end

    local orig_getfont = font.getfont
    font.getfont = function(id)
        if id == 44 then
            return {
                size = 655360,
                characters = {
                    [0xF0001] = { tounicode = "4E00", index = 10 },  -- 一 (not punct)
                }
            }
        end
        return orig_getfont(id)
    end

    test_utils.assert_nil(resolve_original_codepoint(44, 0xF0001))

    font.getfont = orig_getfont
end)

test_utils.run_test("resolve_original_codepoint: caches per font", function()
    for k in pairs(punct._internal.font_tounicode_cache) do
        punct._internal.font_tounicode_cache[k] = nil
    end

    local call_count = 0
    local orig_getfont = font.getfont
    font.getfont = function(id)
        call_count = call_count + 1
        return {
            size = 655360,
            characters = {
                [0xF00A0] = { tounicode = "FF0C", index = 100 },
            }
        }
    end

    -- First call: builds cache
    resolve_original_codepoint(45, 0xF00A0)
    local first_count = call_count

    -- Second call: should use cache, no extra font.getfont call
    resolve_original_codepoint(45, 0xF00A0)
    test_utils.assert_eq(call_count, first_count, "should use cache on second call")

    font.getfont = orig_getfont
end)

-- ============================================================================
-- _internal: get_ink_center_ratio with PUA chars (Issue #71)
-- ============================================================================

local get_ink_center_ratio = punct._internal.get_ink_center_ratio

test_utils.run_test("get_ink_center_ratio: returns 0.5, 0.5 for unknown font", function()
    for k in pairs(punct._internal.font_ink_center_cache) do
        punct._internal.font_ink_center_cache[k] = nil
    end

    local orig_getfont = font.getfont
    font.getfont = function(id) return nil end

    local rx, ry = get_ink_center_ratio(999, 0xFF0C)
    test_utils.assert_eq(rx, 0.5)
    test_utils.assert_eq(ry, 0.5)

    font.getfont = orig_getfont
end)

test_utils.run_test("get_ink_center_ratio: returns 0.5, 0.5 for font without filename", function()
    for k in pairs(punct._internal.font_ink_center_cache) do
        punct._internal.font_ink_center_cache[k] = nil
    end

    local orig_getfont = font.getfont
    font.getfont = function(id) return { size = 655360 } end

    local rx, ry = get_ink_center_ratio(998, 0xFF0C)
    test_utils.assert_eq(rx, 0.5)
    test_utils.assert_eq(ry, 0.5)

    font.getfont = orig_getfont
end)

test_utils.run_test("get_ink_center_ratio: caches x and y ratios for PUA chars", function()
    for k in pairs(punct._internal.font_ink_center_cache) do
        punct._internal.font_ink_center_cache[k] = nil
    end

    -- Mock fontloader to return glyphs with bounding boxes
    local orig_getfont = font.getfont
    local orig_fontloader = fontloader
    font.getfont = function(id)
        if id == 50 then
            return {
                size = 655360,
                filename = "mock_font.otf",
                characters = {
                    -- Standard Unicode comma (glyph index 10)
                    [0xFF0C] = { tounicode = "FF0C", width = 655360, index = 10 },
                    -- PUA vert comma (glyph index 20) - mapped via vert GSUB
                    [0xF00A0] = { tounicode = "FF0C", width = 655360, index = 20 },
                    -- PUA vert ideographic comma (glyph index 21)
                    [0xF0071] = { tounicode = "3001", width = 655360, index = 21 },
                }
            }
        end
        return orig_getfont(id)
    end

    fontloader = {
        open = function(filename)
            return { _filename = filename }
        end,
        to_table = function(raw)
            return {
                glyphcnt = 30,
                glyphs = {
                    -- Index 10: standard comma, cx=(100+400)/2=250, cy=(0+800)/2=400
                    [10] = { unicode = 0xFF0C, width = 1000,
                             boundingbox = { 100, 0, 400, 800 } },
                    -- Index 20: vert comma (PUA), cx=(400+900)/2=650, cy=(200+600)/2=400
                    [20] = { width = 1000,
                             boundingbox = { 400, 200, 900, 600 } },
                    -- Index 21: vert ideo comma (PUA), cx=(100+600)/2=350, cy=(500+800)/2=650
                    [21] = { width = 1000,
                             boundingbox = { 100, 500, 600, 800 } },
                }
            }
        end,
        close = function(raw) end
    }

    -- Standard Unicode char: cx=250/1000=0.25, cy=400/1000=0.4
    local rx, ry = get_ink_center_ratio(50, 0xFF0C)
    test_utils.assert_eq(rx, 0.25, "standard comma ink center x")
    test_utils.assert_eq(ry, 0.4, "standard comma ink center y")

    -- PUA vert comma: cx=650/1000=0.65, cy=400/1000=0.4
    local prx, pry = get_ink_center_ratio(50, 0xF00A0)
    test_utils.assert_eq(prx, 0.65, "PUA vert comma ink center x")
    test_utils.assert_eq(pry, 0.4, "PUA vert comma ink center y")

    -- PUA vert ideographic comma: cx=350/1000=0.35, cy=650/1000=0.65
    local prx2, pry2 = get_ink_center_ratio(50, 0xF0071)
    test_utils.assert_eq(prx2, 0.35, "PUA vert ideo comma ink center x")
    test_utils.assert_eq(pry2, 0.65, "PUA vert ideo comma ink center y")

    -- Restore
    font.getfont = orig_getfont
    fontloader = orig_fontloader
end)

-- ============================================================================
-- _internal: INK_CENTER_CHARS coverage (Issue #71)
-- ============================================================================

test_utils.run_test("INK_CENTER_CHARS: contains expected punctuation", function()
    local chars = punct._internal.INK_CENTER_CHARS
    test_utils.assert_true(chars[0xFF0C] == true)  -- ，
    test_utils.assert_true(chars[0x3001] == true)  -- 、
    test_utils.assert_true(chars[0x3002] == true)  -- 。
    test_utils.assert_true(chars[0xFF0E] == true)  -- ．
    test_utils.assert_true(chars[0xFF1A] == true)  -- ：
    test_utils.assert_true(chars[0xFF1B] == true)  -- ；
    test_utils.assert_true(chars[0xFF01] == true)  -- ！
    test_utils.assert_true(chars[0xFF1F] == true)  -- ？
end)

test_utils.run_test("INK_CENTER_CHARS: does not contain CJK or Latin", function()
    local chars = punct._internal.INK_CENTER_CHARS
    test_utils.assert_nil(chars[0x4E00])   -- 一
    test_utils.assert_nil(chars[0x0041])   -- A
    test_utils.assert_nil(chars[0xF00A0])  -- PUA (not in INK_CENTER_CHARS directly)
end)

-- ============================================================================
-- flatten: 上下文相关收回量的标注（总量 + 始端量）
-- ============================================================================
-- clreq 收回的是「哪一侧」的空白决定字面往哪边让，所以两个量都要标，
-- 只标总量会让渲染把标点对称缩短（PR #132 评审发现的缺陷）。

local function flatten_chars(chars, ctx)
    local constants = require("core.luatex-cn-constants")
    local nodes = {}
    for i, c in ipairs(chars) do
        nodes[i] = test_utils.make_glyph(c, 1)
    end
    punct.flatten(test_utils.link_nodes(nodes), {}, ctx)
    local out = {}
    for i, n in ipairs(nodes) do
        local total = node.direct.get_attribute(n, constants.ATTR_PUNCT_SQUEEZE)
        local head = node.direct.get_attribute(n, constants.ATTR_PUNCT_SQUEEZE_HEAD)
        out[i] = {
            total = total and (total - 1) / 1000 or nil,
            head = head and (head - 1) / 1000 or nil,
        }
    end
    return out
end

local CONTEXT_CTX = {
    style = "mainland", squeeze = true, squeeze_mode = "context",
    adjacent_punct = "1.5", line_start_bracket = "trim",
    line_end_punct = "compress",
}

test_utils.run_test("flatten: 汉字之间的逗号标注为不收回", function()
    local r = flatten_chars({ 0x5B57, 0xFF0C, 0x5B57 }, CONTEXT_CTX)
    test_utils.assert_eq(r[2].total, 0)
    test_utils.assert_eq(r[2].head, 0)
end)

test_utils.run_test("flatten: 句号在结束夹注符号前收回末端半字（始端为 0）", function()
    local r = flatten_chars({ 0x5B57, 0x3002, 0x300D }, CONTEXT_CTX)
    test_utils.assert_eq(r[2].total, 0.5)
    test_utils.assert_eq(r[2].head, 0, "大陆式点号的空白在末端，始端收回必须为 0")
end)

test_utils.run_test("flatten: 开始夹注符号跟在标点后收回始端半字", function()
    local r = flatten_chars({ 0xFF1A, 0x300C, 0x5B57 }, CONTEXT_CTX)
    test_utils.assert_eq(r[2].total, 0.5)
    test_utils.assert_eq(r[2].head, 0.5, "夹注符号的空白在始端，应全部记在始端")
end)

test_utils.run_test("flatten: 脚注标号组内的括号不参与宽度调整", function()
    local constants = require("core.luatex-cn-constants")
    -- ，︻一︼ ——「，」与标号的开括号相邻，但标号组的字幅由 marker 预处理
    -- 按组高分配，不能再叠加标点宽度调整（否则组内括号被挤歪）
    local nodes = {}
    for i, c in ipairs({ 0x5B57, 0xFF0C, 0x3010, 0x4E00, 0x3011, 0x5B57 }) do
        nodes[i] = test_utils.make_glyph(c, 1)
    end
    for i = 3, 5 do
        node.direct.set_attribute(nodes[i], constants.ATTR_FOOTNOTE_MARKER, 12)
    end
    punct.flatten(test_utils.link_nodes(nodes), {}, CONTEXT_CTX)
    test_utils.assert_nil(
        node.direct.get_attribute(nodes[3], constants.ATTR_PUNCT_SQUEEZE),
        "标号组的开括号不应带收回量")
    test_utils.assert_nil(
        node.direct.get_attribute(nodes[5], constants.ATTR_PUNCT_SQUEEZE),
        "标号组的闭括号不应带收回量")
    -- 组外的逗号照常判定，但标号组对它是不透明的：不得因为标号的开括号
    -- 而触发连续标点缩减（clreq 的连续标点缩减针对夹注符号）
    local comma = node.direct.get_attribute(nodes[2], constants.ATTR_PUNCT_SQUEEZE)
    test_utils.assert_eq(comma, 1, "标号前的逗号应占满一字幅")
end)

test_utils.run_test("flatten: legacy 模式不写收回量属性", function()
    local ctx = { style = "mainland", squeeze = true, squeeze_mode = "legacy" }
    local r = flatten_chars({ 0x5B57, 0x3002, 0x300D }, ctx)
    test_utils.assert_nil(r[2].total)
    test_utils.assert_nil(r[2].head)
end)

-- ============================================================================
-- 度量驱动的字面分布（共享层 punct-anchors，差距分析 4.1 第 5 条）
-- ============================================================================

local anchors = require("shared.luatex-cn-punct-anchors")

test_utils.run_test("anchors: 大陆式直排——墨心挪到偏靠锚点", function()
    local em = 655360   -- 10pt
    -- KingHwa 逗号实测 bbox（横排形，墨迹在左下）：{103,-107,309,248}/1000
    local dx, dy = anchors.offsets(0xFF0C, "mainland", "vertical",
        { 103, -107, 309, 248 }, 1000, em)
    local a = anchors.anchor(0xFF0C, "mainland", "vertical")
    -- cx = 0.206 / cy = 0.0705 → 位移 = 锚点 − 墨心
    test_utils.assert_near(dx / em, a.x - 0.206, 0.001)
    test_utils.assert_near(dy / em, a.y - 0.0705, 0.001)
end)

test_utils.run_test("anchors: 大陆式直排是偏靠不是居中（回归守卫）", function()
    -- 曾误取字形 bbox 中心（0.49）当锚点，偏靠整个丢失、退化为居中
    for _, c in ipairs({ 0xFF0C, 0x3001, 0x3002, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F }) do
        local a = anchors.anchor(c, "mainland", "vertical")
        test_utils.assert_true(a.x > 0.7,
            string.format("U+%04X 直排大陆锚点应偏右", c))
    end
    -- 句号在右上：y 锚点高于逗号
    test_utils.assert_true(anchors.anchor(0x3002, "mainland", "vertical").y
        > anchors.anchor(0xFF0C, "mainland", "vertical").y)
end)

test_utils.run_test("anchors: 台湾式居中，横竖同值（TW-Kai 样板零位移）", function()
    for _, mode in ipairs({ "vertical", "horizontal" }) do
        for _, c in ipairs({ 0xFF0C, 0x3002, 0xFF1F }) do
            local a = anchors.anchor(c, "taiwan", mode)
            test_utils.assert_true(math.abs(a.x - 0.5) < 0.05,
                string.format("U+%04X 台湾式锚点应居中", c))
        end
    end
    -- 样板字体（TW-Kai）自身位移应为零：锚点即其实测墨心
    -- TW-Kai ，bbox 中心 (0.495, 0.311)/em
    local dx, dy = anchors.offsets(0xFF0C, "taiwan", "vertical",
        { 425, 241, 565, 381 }, 1000, 655360)  -- 中心恰 (0.495, 0.311)
    test_utils.assert_eq(dx, 0)
    test_utils.assert_eq(dy, 0)
end)

test_utils.run_test("anchors: 大陆式横排靠左下（思源宋体样板）", function()
    for _, c in ipairs({ 0xFF0C, 0x3001, 0x3002 }) do
        local a = anchors.anchor(c, "mainland", "horizontal")
        test_utils.assert_true(a.x < 0.3,
            string.format("U+%04X 横排大陆锚点应偏左", c))
        test_utils.assert_true(a.y < 0.15,
            string.format("U+%04X 横排大陆锚点应偏下", c))
    end
    -- 样板字体（思源宋体）自身位移为零：，bbox 中心 (0.153, -0.039)
    local dx, dy = anchors.offsets(0xFF0C, "mainland", "horizontal",
        { 103, -89, 203, 11 }, 1000, 655360)  -- 中心恰 (0.153, -0.039)
    test_utils.assert_eq(dx, 0)
    test_utils.assert_eq(dy, 0)
end)

test_utils.run_test("anchors: none 预设 / 未收录码位 / 数据不全时返回 nil", function()
    test_utils.assert_nil((anchors.offsets(0xFF0C, "none", "vertical",
        { 0, 0, 500, 500 }, 1000, 655360)))
    test_utils.assert_nil((anchors.offsets(0x300C, "mainland", "vertical",
        { 0, 0, 500, 500 }, 1000, 655360)))   -- 「 夹注符号无锚点
    test_utils.assert_nil((anchors.offsets(0xFF0C, "mainland", "vertical",
        nil, 1000, 655360)))
    test_utils.assert_nil((anchors.offsets(0xFF0C, "mainland", "vertical",
        { 0, 0, 500, 500 }, 0, 655360)))
    test_utils.assert_nil((anchors.offsets(0xFF0C, "mainland", "vertical",
        { 0, 0, 500, 500 }, 1000, nil)))
end)

test_utils.run_test("anchors: 按自身字号缩放（夹注小字）", function()
    local bb = { 103, -107, 309, 248 }
    local dx1 = anchors.offsets(0xFF0C, "mainland", "vertical", bb, 1000, 655360)
    local dx2 = anchors.offsets(0xFF0C, "mainland", "vertical", bb, 1000, 655360 * 2)
    test_utils.assert_near(dx2 / dx1, 2.0, 0.01)
end)

-- ============================================================================
-- 破折号：合字拆解与连排标注（issue #119）
-- ============================================================================

test_utils.run_test("dash_ligature_count: ⸺ / ⸻ 有正式码位", function()
    -- 思源宋体的 ccmp 把 —— 合成 U+2E3A（实测 width ≈ 1.7 em），
    -- 一字一格的竖排网格里必须拆回两个 em dash
    test_utils.assert_eq(punct.dash_ligature_count(0, 0x2E3A), 2)
    test_utils.assert_eq(punct.dash_ligature_count(0, 0x2E3B), 3)
end)

test_utils.run_test("dash_ligature_count: 普通字符不是合字", function()
    test_utils.assert_nil(punct.dash_ligature_count(0, 0x2014))  -- — 本身
    test_utils.assert_nil(punct.dash_ligature_count(0, 0x2026))  -- …
    test_utils.assert_nil(punct.dash_ligature_count(0, 0x4E00))  -- 一
end)

test_utils.run_test("dash_ligature_count: 无码位合字靠 tounicode 识别", function()
    local orig_getfont = font.getfont
    font.getfont = function()
        return { characters = {
            [0xF1000] = { tounicode = "20142014" },   -- —— 合字
            [0xF1001] = { tounicode = "201520152015" }, -- ─── 合字
            [0xF1002] = { tounicode = "20142026" },   -- 破折号+省略号：不是
            [0xF1003] = { tounicode = "2014" },       -- 单个：不是合字
        } }
    end
    test_utils.assert_eq(punct.dash_ligature_count(1, 0xF1000), 2)
    test_utils.assert_eq(punct.dash_ligature_count(1, 0xF1001), 3)
    test_utils.assert_nil(punct.dash_ligature_count(1, 0xF1002))
    test_utils.assert_nil(punct.dash_ligature_count(1, 0xF1003))
    font.getfont = orig_getfont
end)

test_utils.run_test("annotate_rigid_units: 两字幅单元标 2，一般刚性单元标 1", function()
    local constants = require("core.luatex-cn-constants")
    local D = constants.D
    local function seq_of(chars)
        local s = {}
        for i, c in ipairs(chars) do
            s[i] = { node = test_utils.make_direct_node(constants.GLYPH,
                { char = c }), char = c, punct = true }
        end
        return s
    end
    local function rigid(s, i)
        return D.get_attribute(s[i].node, constants.ATTR_RIGID_PREV)
    end
    local function dash_run(s, i)
        return D.get_attribute(s[i].node, constants.ATTR_DASH_RUN)
    end

    -- —— 是两字幅单元：内部字距要归零（=2），且两端都要拉伸墨迹
    local s = seq_of({ 0x2014, 0x2014 })
    punct._internal.annotate_rigid_units(s)
    test_utils.assert_eq(rigid(s, 2), 2)
    test_utils.assert_eq(dash_run(s, 1), 1)
    test_utils.assert_eq(dash_run(s, 2), 1)

    -- …… 同样是两字幅单元，但圆点不能拉伸
    s = seq_of({ 0x2026, 0x2026 })
    punct._internal.annotate_rigid_units(s)
    test_utils.assert_eq(rigid(s, 2), 2)
    test_utils.assert_nil(dash_run(s, 1))

    -- 数字串是一般刚性单元：锁死既有字距，但不归零
    s = seq_of({ 0x31, 0x32 })
    punct._internal.annotate_rigid_units(s)
    test_utils.assert_eq(rigid(s, 2), 1)

    -- 破折号后面跟正文：不是同一个单元
    s = seq_of({ 0x2014, 0x4E00 })
    punct._internal.annotate_rigid_units(s)
    test_utils.assert_nil(rigid(s, 2))
    test_utils.assert_nil(dash_run(s, 1))
end)

print("\nAll core/core-punct-test tests passed!")
