-- luatex-cn-hori-pipeline.lua
-- Node pipeline for the horizontal (clreq) backend.
--
-- pre_linebreak_filter (H1): walks each paragraph and inserts, at every
-- CJK-involved character boundary, the penalty / adjustable glue decided by
-- hori-spacing.lua; Western word spaces get tagged with the western_word
-- adjustment class (clreq 挤压第 2 级 / 拉伸第 1 级). TeX's line breaker then
-- handles break search globally (禁则 = penalty, 可调空间 = glue).
--
-- post_linebreak_filter (H2/H3): re-distributes each line's surplus or
-- shortfall by clreq priority via hori-adjust-line.lua (overriding TeX's
-- proportional distribution, reclaiming the line-final punctuation blank),
-- then draws the inter-line marks (专名号/书名号甲式/着重号) via
-- hori-linemark.lua.
--
-- Standalone: depends only on tex/shared/ and the hori/ siblings (never on
-- the vertical engine's core/).

local spacing = require("hori.luatex-cn-hori-spacing")
local adjust_line = require("hori.luatex-cn-hori-adjust-line")
local linemark = require("hori.luatex-cn-hori-linemark")

local pipeline = {}

local D = node.direct
local GLYPH = node.id("glyph")
local GLUE = node.id("glue")
local KERN = node.id("kern")
local PENALTY = node.id("penalty")
local WHATSIT = node.id("whatsit")
local MATH = node.id("math")

-- Adjustment-class attribute for the H2 redistribution pass
local ATTR_ADJUST_CLASS = luatexbase.attributes.cnhoriadjustclass
    or luatexbase.new_attribute("cnhoriadjustclass")
pipeline.ATTR_ADJUST_CLASS = ATTR_ADJUST_CLASS

-- Runtime options (set via setup)
local opts = {
    style = "mainland",
    level = "basic",
    cjk_latin_space = true,
    inter_cjk_stretch = 0.05,
    line_adjust = true,          -- H2 priority redistribution on/off
    line_end_punct = "compress", -- "compress" | "natural"
}

--- Configure the pipeline.
-- @param o (table) { style, level, cjk_latin_space, inter_cjk_stretch,
--   line_adjust, line_end_punct }
function pipeline.setup(o)
    if not o then return end
    if o.style ~= nil then opts.style = o.style end
    if o.level ~= nil then opts.level = o.level end
    if o.cjk_latin_space ~= nil then opts.cjk_latin_space = o.cjk_latin_space end
    if o.inter_cjk_stretch ~= nil then opts.inter_cjk_stretch = o.inter_cjk_stretch end
    if o.line_adjust ~= nil then opts.line_adjust = o.line_adjust end
    if o.line_end_punct ~= nil then opts.line_end_punct = o.line_end_punct end
end

-- Interword space glue subtypes (LuaTeX: spaceskip / xspaceskip; ordinary
-- font spaces are emitted as spaceskip)
local SPACE_SUBTYPES = { [13] = true, [14] = true }

local function em_size(glyph_d)
    local fid = D.getfield(glyph_d, "font")
    local f = fid and font.getfont(fid)
    return (f and f.size) or 655360  -- fallback 10pt
end

local function make_penalty(value)
    local p = D.new(PENALTY)
    D.setfield(p, "penalty", value)
    return p
end

local function make_glue(width_sp, stretch_sp, shrink_sp, class_name)
    local g = D.new(GLUE)
    D.setfield(g, "width", width_sp)
    D.setfield(g, "stretch", stretch_sp)
    D.setfield(g, "shrink", shrink_sp)
    local code = spacing.ADJUST_CLASS_CODES[class_name]
    if code then
        D.set_attribute(g, ATTR_ADJUST_CLASS, code)
    end
    return g
end

--- Process one node list: insert boundary nodes between adjacent glyphs.
-- Boundaries are only considered between glyphs separated by nothing or by
-- font kerns; an existing glue or penalty between two glyphs means the
-- document (or TeX) already decided that boundary — leave it alone. Math is
-- skipped wholesale; boxes/discretionaries reset the boundary context.
--
-- Insertion is done by relinking between the current node's predecessor and
-- the current node; since a boundary always has a preceding glyph, the list
-- head never changes.
-- @param head_d (direct node) list head
-- @return (direct node) list head (unchanged)
function pipeline.process(head_d)
    local prev_glyph = nil
    local prev_node = nil     -- node immediately before curr in the walk
    local blocked = false     -- an intervening glue/penalty blocks insertion
    local math_level = 0

    local curr = head_d
    while curr do
        local id = D.getid(curr)

        if id == MATH then
            -- subtype 0 = math on, 1 = math off
            if D.getsubtype(curr) == 0 then
                math_level = math_level + 1
            else
                math_level = math_level - 1
                if math_level < 0 then math_level = 0 end
            end
            prev_glyph = nil
        elseif math_level > 0 then
            -- inside math: ignore everything
        elseif id == GLYPH then
            if prev_glyph and not blocked then
                local a = D.getfield(prev_glyph, "char")
                local c = D.getfield(curr, "char")
                if a and c then
                    local action = spacing.boundary(a, c, opts)
                    if action and action.glue then
                        local em = em_size(prev_glyph)
                        local g = make_glue(
                            math.floor(action.glue.width * em + 0.5),
                            math.floor(action.glue.stretch * em + 0.5),
                            math.floor(action.glue.shrink * em + 0.5),
                            action.glue.class)
                        -- prev_node → [penalty] → glue → curr
                        if action.penalty then
                            local p = make_penalty(action.penalty)
                            D.setlink(prev_node, p)
                            D.setlink(p, g)
                        else
                            D.setlink(prev_node, g)
                        end
                        D.setlink(g, curr)
                    end
                end
            end
            prev_glyph = curr
            blocked = false
        elseif id == KERN or id == WHATSIT then
            -- transparent for boundary purposes (font kerns, marks)
        elseif id == GLUE or id == PENALTY then
            -- The boundary already has spacing/break semantics; skip it.
            -- Word spaces (from source blanks) get the western_word class so
            -- the H2 pass manages them at clreq 挤压第 2 级 / 拉伸第 1 级.
            if id == GLUE and SPACE_SUBTYPES[D.getsubtype(curr)]
                and D.getfield(curr, "width") > 0
                and not D.get_attribute(curr, ATTR_ADJUST_CLASS) then
                D.set_attribute(curr, ATTR_ADJUST_CLASS,
                    spacing.ADJUST_CLASS_CODES.western_word)
            end
            blocked = true
        else
            -- boxes, discretionaries, rules, dirs, ...: reset context
            prev_glyph = nil
            blocked = false
        end

        prev_node = curr
        curr = D.getnext(curr)
    end

    return head_d
end

-- ============================================================================
-- Callback registration
-- ============================================================================

local CALLBACK_NAME = "luatexcn.hori.pre_linebreak"
local POST_CALLBACK_NAME = "luatexcn.hori.post_linebreak"
local enabled = false

local function pre_linebreak(head, groupcode)
    local d = D.todirect(head)
    d = pipeline.process(d)
    return D.tonode(d)
end

local function post_linebreak(head, groupcode)
    local d = D.todirect(head)
    if opts.line_adjust then
        d = adjust_line.process_lines(d, ATTR_ADJUST_CLASS, opts)
    end
    d = linemark.decorate(d)
    return D.tonode(d)
end

--- Register the pre/post_linebreak_filter pair (idempotent).
function pipeline.enable()
    if enabled then return end
    luatexbase.add_to_callback("pre_linebreak_filter", pre_linebreak, CALLBACK_NAME)
    luatexbase.add_to_callback("post_linebreak_filter", post_linebreak, POST_CALLBACK_NAME)
    enabled = true
end

--- Remove the callbacks (for tests / package unloading).
function pipeline.disable()
    if not enabled then return end
    luatexbase.remove_from_callback("pre_linebreak_filter", CALLBACK_NAME)
    luatexbase.remove_from_callback("post_linebreak_filter", POST_CALLBACK_NAME)
    enabled = false
end

return pipeline
