-- luatex-cn-hori-spacing.lua
-- Pure boundary-decision logic for the horizontal (clreq) pipeline: given two
-- adjacent characters, decide what to insert between them — a break penalty
-- (from the shared kinsoku rules) and/or an adjustable glue (inter-CJK
-- break/stretch point, or the clreq CJK–Western spacing).
--
-- clreq rules implemented here:
--   * 中西混排: 汉字与西文字母、数字间使用不多于 1/4 汉字宽的字距，
--     行内调整时可挤压至 1/8、拉伸至 1/2。
--   * 例外: 在中文点号前后、开始夹注符号之后、结束夹注符号之前的西文，
--     不调整字距或加入空白。（行首/行尾不加由 TeX 断行天然保证：
--     断点处的 glue 会被丢弃。）
--   * 行首行尾禁则 / 符号分离禁则: 由 shared/kinsoku 提供 penalty。
--
-- Pure Lua, zero TeX dependency (node insertion lives in hori-pipeline.lua).
-- All glue amounts are em ratios; the pipeline multiplies by the font size.

local punct_table = require("shared.luatex-cn-punct-table")
local kinsoku = require("shared.luatex-cn-kinsoku")

local M = {}

-- Adjustment classes carried on inserted glues (attribute values consumed by
-- the H2 post-linebreak redistribution; codes must stay stable).
M.ADJUST_CLASS_CODES = {
    fallback     = 1, -- inter-hanzi gap: even-distribution stretch of last resort
    cjk_western  = 2, -- CJK–Western spacing (clreq shrink step 6 / stretch step 2)
    western_word = 3, -- Western word space (clreq shrink step 2 / stretch step 1)
    -- Punctuation blank-side shrink, keyed by the shared table's shrink
    -- classes (clreq compression steps 3/4/5/7):
    interpunct     = 4,
    bracket        = 5,
    comma_group    = 6,
    fullstop_group = 7,
}

-- ============================================================================
-- Character kind classification
-- ============================================================================

local function is_han(c)
    return (c >= 0x4E00 and c <= 0x9FFF)      -- CJK Unified
        or (c >= 0x3400 and c <= 0x4DBF)      -- Ext A
        or (c >= 0xF900 and c <= 0xFAFF)      -- Compatibility
        or (c >= 0x20000 and c <= 0x3FFFF)    -- Ext B+
        or c == 0x3005 or c == 0x3007 or c == 0x303B  -- 々 〇 〻
end

local function is_fullwidth_alnum(c)
    return (c >= 0xFF10 and c <= 0xFF19)      -- ０-９
        or (c >= 0xFF21 and c <= 0xFF3A)      -- Ａ-Ｚ
        or (c >= 0xFF41 and c <= 0xFF5A)      -- ａ-ｚ
end

local function is_latin(c)
    return (c >= 0x41 and c <= 0x5A)
        or (c >= 0x61 and c <= 0x7A)
        or (c >= 0xC0 and c <= 0x24F and c ~= 0xD7 and c ~= 0xF7)
end

local function is_digit(c)
    return c >= 0x30 and c <= 0x39
end

--- Classify a codepoint for boundary decisions.
-- @param c (number) Unicode codepoint
-- @return (string) "cjk" | "cjk_punct" | "western" | "other"
function M.kind(c)
    local cls = punct_table.class_of(c)
    if cls then
        -- Inter-line marks have no inline advance; treat as other
        if cls == "linemark" or cls == "emphasis" then return "other" end
        return "cjk_punct"
    end
    if is_han(c) or is_fullwidth_alnum(c) then return "cjk" end
    if is_latin(c) or is_digit(c) then return "western" end
    return "other"
end

-- clreq exception set for CJK–Western spacing: no spacing next to pause/stop
-- marks, after an opening bracket, or before a closing bracket.
local function suppresses_western_spacing(c)
    if punct_table.is_point(c) then return true end
    local cls = punct_table.class_of(c)
    return cls == "open" or cls == "close"
end

-- ============================================================================
-- Boundary decision
-- ============================================================================

local DEFAULT_OPTS = {
    style = "mainland",        -- punctuation style: mainland | taiwan | none
    level = "basic",           -- kinsoku level
    cjk_latin_space = true,    -- insert the 1/4 em CJK–Western spacing
    inter_cjk_stretch = 0.05,  -- em; stretch of last resort between hanzi
                               -- (H2 replaces TeX's proportional use of it
                               -- with the priority-ordered redistribution)
}

-- Shrinkable blank contributed by a punctuation glyph to the boundary on one
-- of its sides (clreq 标点符号的宽度调整: the fullwidth glyph carries its
-- blank; compression removes up to that blank). side "both" splits the
-- shrink between the two boundaries. Style "none" = 不调整 preset.
-- @return shrink_em (number), shrink_class (string|nil)
local function punct_side_shrink(c, which_side, style)
    if style == "none" then return 0, nil end
    local info = punct_table.space_info(c, style, "horizontal")
    if not info or info.shrink <= 0 then return 0, nil end
    local cls = punct_table.shrink_class_of(c, style, "horizontal")
    if info.side == which_side then
        return info.shrink, cls
    elseif info.side == "both" then
        return info.shrink / 2, cls
    end
    return 0, nil
end

--- Decide what to insert between two adjacent characters.
-- @param prev (number) codepoint before the boundary
-- @param next_c (number) codepoint after the boundary
-- @param opts (table|nil) { level, cjk_latin_space, inter_cjk_stretch }
-- @return (table|nil) nil = insert nothing (pure Western boundary: TeX's own
--   spacing/hyphenation applies). Otherwise:
--   {
--     penalty = 10000|nil,     -- break prohibition (before the glue)
--     glue = {                 -- adjustable break point, em ratios
--       width, shrink, stretch,
--       class = "fallback"|"cjk_western",
--     } | nil,
--   }
function M.boundary(prev, next_c, opts)
    opts = opts or DEFAULT_OPTS
    local pk = M.kind(prev)
    local nk = M.kind(next_c)

    -- Pure Western/other boundary: leave it to TeX (word spaces come from
    -- the source; hyphenation provides break points — clreq: 西文单词在
    -- 可使用连字符处之外不得分隔，正是 TeX 的默认行为)
    local prev_cjk = (pk == "cjk" or pk == "cjk_punct")
    local next_cjk = (nk == "cjk" or nk == "cjk_punct")
    if not prev_cjk and not next_cjk then
        return nil
    end

    local forbidden = kinsoku.no_break_between(prev, next_c,
        { level = opts.level or DEFAULT_OPTS.level })

    local glue
    if (prev_cjk and nk == "western") or (pk == "western" and next_cjk) then
        -- CJK–Western boundary: 1/4 em spacing unless suppressed by the
        -- adjacent punctuation exception
        local cjk_char = prev_cjk and prev or next_c
        local space_on = opts.cjk_latin_space
        if space_on == nil then space_on = DEFAULT_OPTS.cjk_latin_space end
        if space_on and not suppresses_western_spacing(cjk_char) then
            glue = { width = 0.25, shrink = 0.125, stretch = 0.25,
                     class = "cjk_western" }
        else
            glue = { width = 0, shrink = 0, stretch = 0, class = "fallback" }
        end
    elseif prev_cjk and next_cjk then
        -- Inter-CJK boundary: zero-width break point with a small stretch
        -- of last resort (clreq: 行内文字原则上密排；拉伸兜底均分)
        local st = opts.inter_cjk_stretch or DEFAULT_OPTS.inter_cjk_stretch
        glue = { width = 0, shrink = 0, stretch = st, class = "fallback" }
    else
        -- CJK next to "other" (symbols etc.): break point without spacing
        glue = { width = 0, shrink = 0, stretch = 0, class = "fallback" }
    end

    -- Punctuation blank-side shrink (clreq 标点宽度调整): the trailing blank
    -- of prev / leading blank of next may be compressed at this boundary.
    -- TeX's proportional use of this shrink is an approximation; the H2 pass
    -- redistributes it by clreq priority using the class attribute.
    -- Both sides may contribute (adjacent punctuation: clreq allows 2 → 1.5
    -- → 1 em by removing both half-blanks); the class comes from the larger
    -- contributor.
    local style = opts.style or DEFAULT_OPTS.style
    local prev_s, prev_cls = 0, nil
    local next_s, next_cls = 0, nil
    if pk == "cjk_punct" then
        prev_s, prev_cls = punct_side_shrink(prev, "end", style)
    end
    if nk == "cjk_punct" then
        next_s, next_cls = punct_side_shrink(next_c, "start", style)
    end
    local shrink_amount = prev_s + next_s
    if shrink_amount > 0 then
        glue.shrink = glue.shrink + shrink_amount
        local cls = (next_s > prev_s) and next_cls or prev_cls
        if cls then glue.class = cls end
    end

    return {
        penalty = forbidden and 10000 or nil,
        glue = glue,
    }
end

return M
