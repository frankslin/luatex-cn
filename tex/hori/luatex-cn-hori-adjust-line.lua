-- luatex-cn-hori-adjust-line.lua
-- H2: per-line second-pass space redistribution (post_linebreak_filter).
--
-- TeX's line breaker distributes surplus/shortfall PROPORTIONALLY over every
-- glue's stretch/shrink; clreq instead mandates a strict priority order
-- (挤压 7 级 / 拉伸 2 级 + 兜底均分). This pass re-solves each finished line
-- with shared/adjust.lua and overwrites the managed glues with the solved
-- widths, so the priority order — not TeX's badness proportion — decides
-- which gap gives or takes space.
--
-- It also fixes the line-end punctuation inversion the pre-linebreak stage
-- cannot express: the glue at a chosen break point is DISCARDED, so the
-- trailing blank inside a line-final 。，、； glyph survives at full width
-- while earlier gaps get squeezed. Here the blank is reclaimed with a
-- negative kern after the final glyph (clreq 挤压第 1 级: 位于行末的标点
-- 调成固定半字宽) and the recovered space is re-distributed by priority.
--
-- Only glues carrying ATTR_ADJUST_CLASS are touched (HR1); lines containing
-- infinite glue (\hfill, \parfillskip — i.e. the last line of a paragraph)
-- are skipped wholesale.
--
-- The planning half (plan) is pure Lua for texlua unit tests; only
-- process()/process_lines() touch nodes.

local adjust = require("shared.luatex-cn-adjust")
local punct_table = require("shared.luatex-cn-punct-table")
local spacing = require("hori.luatex-cn-hori-spacing")

local M = {}

-- Reverse map: attribute code → class name
local CODE_TO_CLASS = {}
for name, code in pairs(spacing.ADJUST_CLASS_CODES) do
    CODE_TO_CLASS[code] = name
end
M.CODE_TO_CLASS = CODE_TO_CLASS

-- Solver roles per adjust class. Punctuation blank classes shrink only;
-- word spacing and CJK–Western spacing shrink and stretch (clreq 拉伸 2 级);
-- fallback gaps take the even-distribution remainder.
local CLASS_ROLE = {
    fallback       = { fallback = true },
    cjk_western    = { shrink = "cjk_western", stretch = "cjk_western" },
    western_word   = { shrink = "western_word", stretch = "western_word" },
    interpunct     = { shrink = "interpunct" },
    bracket        = { shrink = "bracket" },
    comma_group    = { shrink = "comma_group" },
    fullstop_group = { shrink = "fullstop_group" },
}

-- ============================================================================
-- Pure planning
-- ============================================================================

--- Plan the redistribution for one line.
-- @param gaps (table) array of managed gaps, each
--   { width, stretch, shrink (sp), class (string), effective (sp: the width
--     TeX's proportional distribution actually gave this gap) }
-- @param line_end (table|nil) { blank = sp } — compressible trailing blank
--   inside the line-final punctuation glyph, or nil if the line does not end
--   in such a glyph
-- @param opts (table|nil) { line_end_punct = "compress"|"natural" }
--   compress (default): always reclaim the full trailing blank (行末标点
--     固定半字宽) and re-give the space to the line by stretch priority;
--   natural: reclaim only when the line is over-tight (挤压第 1 级 only).
-- @return (table|nil) { widths = sp array parallel to gaps,
--   line_end_kern = sp (≤ 0) } — nil when there is nothing to do.
function M.plan(gaps, line_end, opts)
    local mode = (opts and opts.line_end_punct) or "compress"
    local blank = line_end and line_end.blank or 0
    if #gaps == 0 and blank <= 0 then return nil end

    -- Total space TeX allocated to the managed region: what the gaps
    -- effectively occupy plus the punctuation blank as laid out.
    local target = blank
    local solver_gaps = {}
    local can_absorb = false
    for i, g in ipairs(gaps) do
        target = target + g.effective
        local role = CLASS_ROLE[g.class] or {}
        solver_gaps[i] = {
            width = g.width,
            min = g.width - (g.shrink or 0),
            max = g.width + (g.stretch or 0),
            shrink_class = role.shrink,
            stretch_class = role.stretch,
            fallback = role.fallback or false,
        }
        if role.fallback or role.stretch then can_absorb = true end
    end

    local kern = 0
    if blank > 0 then
        if mode == "compress" and can_absorb then
            -- Reclaim the whole blank; the solver stretches the line's gaps
            -- to fill the recovered space (fallback distribution is unbounded,
            -- so the target is always reachable).
            kern = -blank
        else
            -- Natural mode (or nothing can absorb the space): the blank is a
            -- shrink-only gap at clreq priority 1 — reclaimed only as far as
            -- the line's tightness demands.
            solver_gaps[#solver_gaps + 1] = {
                width = blank, min = 0, max = blank,
                shrink_class = "line_end_punct",
            }
        end
    end
    if #solver_gaps == 0 then
        -- Only a blank to compress and nothing to give the space to
        return nil
    end

    local solved = adjust.solve(target, solver_gaps)

    -- Convert to integer sp; push the rounding remainder into the last gap
    -- so the repack comes out exact (±1 sp). The rounding baseline is the
    -- solver's achieved total, NOT the target — when the solver cannot reach
    -- the target (deficit) the gaps must keep their best-effort widths.
    local widths = {}
    local acc = 0
    for i = 1, #gaps do
        widths[i] = math.floor(solved.widths[i] + 0.5)
        acc = acc + widths[i]
    end
    local managed_total = solved.total
    if blank > 0 and kern == 0 then
        -- natural mode: the virtual gap's solved width is the kept blank
        local virtual_solved = solved.widths[#solver_gaps]
        kern = math.floor(virtual_solved + 0.5) - blank
        managed_total = managed_total - virtual_solved
    end
    if #gaps > 0 then
        widths[#gaps] = widths[#gaps]
            + (math.floor(managed_total + 0.5) - acc)
    end

    return { widths = widths, line_end_kern = kern }
end

--- Reclaimable trailing space (em ratio) of a line-final punctuation glyph.
-- Normal mode: the end-side share of its adjustable blank (挤压第 1 级,
-- 半字宽). Hanging mode (行尾点号悬挂, opt-in): a line-final pause/stop mark
-- gives up its WHOLE advance — the glyph hangs entirely in the margin.
-- @param char (number) codepoint
-- @param style (string) "mainland" | "taiwan" | "none"
-- @param hanging (boolean|nil) 行尾点号悬挂 enabled
-- @return (number) em ratio ≥ 0
function M.line_end_blank_em(char, style, hanging)
    if style == "none" then return 0 end
    if hanging and punct_table.is_point(char) then
        return punct_table.width_of(char, style) or 0
    end
    local info = punct_table.space_info(char, style, "horizontal")
    if not info or info.shrink <= 0 then return 0 end
    if info.side == "end" then return info.shrink end
    if info.side == "both" then return info.shrink / 2 end
    return 0
end

-- ============================================================================
-- Node application
-- ============================================================================

local D = node.direct
local HLIST = node.id("hlist")
local GLYPH = node.id("glyph")
local GLUE = node.id("glue")
local KERN = node.id("kern")
local PENALTY = node.id("penalty")
local WHATSIT = node.id("whatsit")

local GLUE_RIGHTSKIP = 9
local GLUE_PARFILLSKIP = 15

local function em_size(glyph_d)
    local fid = D.getfield(glyph_d, "font")
    local f = fid and font.getfont(fid)
    return (f and f.size) or 655360
end

-- Effective width of a glue inside a packed hlist (TeX's proportional
-- distribution applied). node.direct.effective_glue does exactly this.
local function effective_glue(g, line)
    return D.effective_glue(g, line) or D.getfield(g, "width")
end

--- Redistribute one packed line (hlist). Mutates glue widths, may append a
-- negative kern after the final punctuation glyph, and repacks to recompute
-- the box glue set. Skips lines with infinite glue or nothing managed.
-- @param line (direct node) hlist of subtype line
-- @param attr (number) ATTR_ADJUST_CLASS attribute id
-- @param opts (table) { style, line_end_punct }
-- @return (boolean) whether the line was modified
function M.process_line(line, attr, opts)
    local head = D.getlist(line)
    if not head then return false end

    local gaps, gap_nodes = {}, {}
    local last_glyph, tail_clean = nil, true
    local n = head
    while n do
        local id = D.getid(n)
        if id == GLUE then
            local subtype = D.getsubtype(n)
            if subtype == GLUE_PARFILLSKIP
                or D.getfield(n, "stretch_order") > 0
                or D.getfield(n, "shrink_order") > 0 then
                return false -- last line of paragraph / \hfill: hands off
            end
            local code = D.get_attribute(n, attr)
            local class = code and CODE_TO_CLASS[code]
            if class then
                gaps[#gaps + 1] = {
                    width = D.getfield(n, "width"),
                    stretch = D.getfield(n, "stretch"),
                    shrink = D.getfield(n, "shrink"),
                    class = class,
                    effective = effective_glue(n, line),
                }
                gap_nodes[#gap_nodes + 1] = n
            end
            if subtype ~= GLUE_RIGHTSKIP then tail_clean = false end
        elseif id == GLYPH then
            last_glyph = n
            tail_clean = true
        elseif id == KERN or id == PENALTY or id == WHATSIT then
            -- transparent for the "is the punctuation truly line-final" test
        else
            last_glyph = nil
            tail_clean = false
        end
        n = D.getnext(n)
    end

    local line_end = nil
    if last_glyph and tail_clean then
        local c = D.getfield(last_glyph, "char")
        local blank_em = c
            and M.line_end_blank_em(c, opts.style, opts.hanging_punct) or 0
        if blank_em > 0 then
            line_end = {
                blank = math.floor(blank_em * em_size(last_glyph) + 0.5),
            }
        end
    end

    local result = M.plan(gaps, line_end, opts)
    if not result then return false end

    for i, g in ipairs(gap_nodes) do
        D.setfield(g, "width", result.widths[i])
        D.setfield(g, "stretch", 0)
        D.setfield(g, "shrink", 0)
    end
    if result.line_end_kern ~= 0 and last_glyph then
        local k = D.new(KERN)
        D.setfield(k, "kern", result.line_end_kern)
        D.insert_after(head, last_glyph, k)
    end

    -- Repack so the box's glue_set reflects the now-rigid managed glues;
    -- any residual lands on whatever flexibility the line still has.
    local packed = D.hpack(head, D.getfield(line, "width"), "exactly")
    D.setfield(line, "glue_set", D.getfield(packed, "glue_set"))
    D.setfield(line, "glue_sign", D.getfield(packed, "glue_sign"))
    D.setfield(line, "glue_order", D.getfield(packed, "glue_order"))
    D.setlist(packed, nil)
    D.flush_node(packed)
    return true
end

--- Walk a post_linebreak vertical list and redistribute every line.
-- @param head_d (direct node) vlist content from post_linebreak_filter
-- @param attr (number) ATTR_ADJUST_CLASS attribute id
-- @param opts (table) { style, line_end_punct }
-- @return (direct node) head (unchanged)
function M.process_lines(head_d, attr, opts)
    local n = head_d
    while n do
        if D.getid(n) == HLIST and D.getsubtype(n) == 1 then
            M.process_line(n, attr, opts)
        end
        n = D.getnext(n)
    end
    return head_d
end

return M
