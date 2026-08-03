-- luatex-cn-kinsoku.lua
-- Line-breaking prohibition rules from clreq:
--   * "Prohibition rules for line start and line end" (行首行尾禁则),
--     four strictness levels: none / basic / gb / strict.
--   * "Prohibition rules for unbreakable punctuation" (符号分离禁则):
--     two-em punctuation units, numeral runs, numeral + unit suffix,
--     sign prefix + numeral, currency + numeral, Western words.
--
-- Pure Lua, zero TeX dependency. Outputs are backend-neutral:
--   * horizontal backend: penalty_between() → TeX penalty value
--   * vertical backend:   check_wrap() → violation kind, then
--     resolve_overflow() → squeeze-in or push-out (代价比较基于 adjust.solve，
--     后端只负责组装两个候选的 gap 序列)
-- Interface contract: ai_must_read/clreq-shared-core.md
--
-- Superscript/subscript/annotation-mark separation rules need node
-- attributes and therefore live in the backends, not here.

local punct_table = require("shared.luatex-cn-punct-table")
local adjust = require("shared.luatex-cn-adjust")

local M = {}

M.LEVELS = { none = 0, basic = 1, gb = 2, strict = 3 }

local DEFAULT_LEVEL = "basic" -- clreq: 这是最推荐的方法

local FORBIDDEN_PENALTY = 10000

-- ============================================================================
-- Character sets for the unbreakable rules (符号分离禁则)
-- ============================================================================

local function is_digit(c)
    return (c >= 0x30 and c <= 0x39)          -- 0-9
        or (c >= 0xFF10 and c <= 0xFF19)      -- ０-９
end

local function is_western_letter(c)
    return (c >= 0x41 and c <= 0x5A)          -- A-Z
        or (c >= 0x61 and c <= 0x7A)          -- a-z
        or (c >= 0xC0 and c <= 0x24F          -- Latin-1 supp / Extended A-B
            and c ~= 0xD7 and c ~= 0xF7)      -- × ÷ are not letters
end

-- Unit suffixes that must not be separated from a preceding numeral
-- (clreq: 百分号、千分号、度数符号与其前面的阿拉伯数字之间不能拆).
local UNIT_SUFFIX = {
    [0x25] = true,    -- %
    [0xFF05] = true,  -- ％
    [0x2030] = true,  -- ‰
    [0x2031] = true,  -- ‱
    [0xB0] = true,    -- °
    [0x2103] = true,  -- ℃
    [0x2109] = true,  -- ℉
    [0x2032] = true,  -- ′
    [0x2033] = true,  -- ″
}

-- Sign prefixes that must not be separated from a following numeral
-- (clreq: 正号、负号、正负号与其后面的阿拉伯数字之间不能拆).
local SIGN_PREFIX = {
    [0x2B] = true,    -- +
    [0xFF0B] = true,  -- ＋
    [0x2D] = true,    -- - (as sign; also connector, both unbreakable here)
    [0xFF0D] = true,  -- －
    [0xB1] = true,    -- ±
    [0x2212] = true,  -- − minus sign
}

-- Currency symbols placed before the numeral (clreq: 前置货币符号).
local CURRENCY_PREFIX = {
    [0x24] = true,    -- $
    [0xFF04] = true,  -- ＄
    [0xA2] = true,    -- ¢
    [0xA3] = true,    -- £
    [0xFFE1] = true,  -- ￡
    [0xA5] = true,    -- ¥
    [0xFFE5] = true,  -- ￥
    [0x20AC] = true,  -- €
    [0xFFE0] = true,  -- ￠
}

-- Currency symbols placed after the numeral (clreq: 后置货币符号，如越南盾).
local CURRENCY_SUFFIX = {
    [0x20AB] = true,  -- ₫
}

-- ============================================================================
-- Line start / line end prohibition (delegated to the shared table)
-- ============================================================================

--- Whether `char` may not appear at line start under `level`.
-- @param char (number) Unicode codepoint
-- @param level (string) "none"|"basic"|"gb"|"strict"
-- @return (boolean)
function M.forbid_line_start(char, level)
    return punct_table.forbid_line_start(char, level or DEFAULT_LEVEL)
end

--- Whether `char` may not appear at line end under `level`.
-- @param char (number) Unicode codepoint
-- @param level (string) "none"|"basic"|"gb"|"strict"
-- @return (boolean)
function M.forbid_line_end(char, level)
    return punct_table.forbid_line_end(char, level or DEFAULT_LEVEL)
end

-- ============================================================================
-- Break opportunity between two adjacent characters
-- ============================================================================

--- Whether a line break between `prev` and `next` is forbidden.
-- Rules are checked in clreq order; the first hit wins.
-- @param prev (number) codepoint before the break candidate
-- @param next_c (number) codepoint after the break candidate
-- @param opts (table|nil) { level = "none"|"basic"|"gb"|"strict" }
-- @return (boolean) forbidden
-- @return (string|nil) reason tag (for tests/debugging):
--   "forbid_start" | "forbid_end" | "unbreakable_pair" | "digit_run" |
--   "digit_suffix" | "sign_prefix" | "currency" | "western_word"
function M.no_break_between(prev, next_c, opts)
    local level = (opts and opts.level) or DEFAULT_LEVEL

    -- 1. Two-em punctuation unit (——, ……, ⋯⋯, and stacked ？！ forms).
    -- Checked before the start/end prohibitions: it is the stronger claim —
    -- not merely "no break here" but "rigid interior" (no stretch/shrink),
    -- and callers key that off this reason tag. 叠加符号（？！等）本身也是
    -- 行首禁则字符，若先查禁则会把原因错报成 forbid_start，刚性就丢了。
    -- For runs longer than one pair, clreq allows breaking between pairs;
    -- callers with run context use pair_boundary_breakable() to lift this
    -- rule at pair boundaries.
    if punct_table.is_unbreakable_pair(prev, next_c) then
        return true, "unbreakable_pair"
    end

    -- 2/3. Line start / line end prohibition
    if punct_table.forbid_line_start(next_c, level) then
        return true, "forbid_start"
    end
    if punct_table.forbid_line_end(prev, level) then
        return true, "forbid_end"
    end

    -- 4. Numeral run (阿拉伯数字应作为一个整体)
    if is_digit(prev) and is_digit(next_c) then
        return true, "digit_run"
    end

    -- 5. Numeral + unit suffix (%, ‰, °, ℃ …)
    if is_digit(prev) and UNIT_SUFFIX[next_c] then
        return true, "digit_suffix"
    end

    -- 6. Sign prefix + numeral (+, -, ±)
    if SIGN_PREFIX[prev] and is_digit(next_c) then
        return true, "sign_prefix"
    end

    -- 7. Currency symbol + numeral (both placements)
    if CURRENCY_PREFIX[prev] and is_digit(next_c) then
        return true, "currency"
    end
    if is_digit(prev) and CURRENCY_SUFFIX[next_c] then
        return true, "currency"
    end

    -- 8. Western word: no break inside letter sequences except after an
    -- explicit hyphen (clreq: 在可使用连字符处之外，不得分隔为两行)
    if is_western_letter(prev) and is_western_letter(next_c) then
        return true, "western_word"
    end

    return false, nil
end

--- Penalty value for the break candidate between `prev` and `next`
-- (horizontal backend: inserted before TeX's line breaker runs).
-- @param prev (number) codepoint
-- @param next_c (number) codepoint
-- @param opts (table|nil) { level = ... }
-- @return (number) 10000 if forbidden, 0 otherwise
function M.penalty_between(prev, next_c, opts)
    local forbidden = M.no_break_between(prev, next_c, opts)
    return forbidden and FORBIDDEN_PENALTY or 0
end

--- Wrap-point check for the vertical backend: the column is full after
-- `last_char`, and `next_char` would start the next column.
-- @param last_char (number) codepoint at the current column end
-- @param next_char (number) codepoint that would start the next column
-- @param opts (table|nil) { level = ... }
-- @return (string|nil) "start_violation" if next_char may not start a line,
--   "end_violation" if last_char may not end a line, nil if the wrap is fine.
--   How to resolve the violation is decided by resolve_overflow() below; the
--   backend only assembles the two candidate gap sets.
function M.check_wrap(last_char, next_char, opts)
    local level = (opts and opts.level) or DEFAULT_LEVEL
    if next_char and punct_table.forbid_line_start(next_char, level) then
        return "start_violation"
    end
    if last_char and punct_table.forbid_line_end(last_char, level) then
        return "end_violation"
    end
    return nil
end

-- ============================================================================
-- Squeeze-in vs push-out decision (禁则的解决方式)
-- ============================================================================

local COST_EPS = 1e-9

-- 代价的比较次序就是 clreq 的挤压优先顺序：越靠后的类越「贵」（越是最后
-- 手段）。拉伸类 western_word / cjk_western 已在其中；兜底均分动的是字距，
-- 归入 inter_char。
local COST_ORDER = adjust.SHRINK_ORDER
local LAST_RESORT = COST_ORDER[#COST_ORDER]   -- "inter_char"

--- 一个候选排布的形变剖面：按类记下该类里被动用得最狠的那个 gap 动了多少。
--
-- **不能把各类形变加权求和**：clreq 的优先顺序是词典序（第 1 级用尽才轮到
-- 第 2 级），不是带权重的折扣。把逗号空白收满 0.5 em 在 clreq 语义里是零
-- 代价的正常操作，而线性权重会把它算成「形变 0.5 的昂贵操作」——量级差
-- 远大于 5 与 8 的权重差，于是「多给一个规范允许的挤压手段」反而让这个
-- 候选更贵。实测（4000 组随机列）会翻转约 13% 的决策，且方向一律是把
-- 「字距零形变」的挤进方案judged 成不如「字距全动」的推出方案。
--
-- 取每类的最大值而不是总和：类内是同时、同等量处理（clreq 原文），最大值
-- 就是「这一类被动用的程度」，且与 gap 个数无关，两个候选 gap 数不同也可比。
--
-- @return (table|nil) class → 最大形变量；nil 表示该候选不可行（装不下）
local function candidate_profile(target, gaps)
    local r = adjust.solve(target, gaps)
    if r.deficit > COST_EPS then
        return nil, r          -- 全部触底仍装不下
    end
    local prof = {}
    for _, class in ipairs(COST_ORDER) do prof[class] = 0 end
    for i, g in ipairs(gaps) do
        local w = g.width
        local min = g.min or w
        local max = g.max or w
        if max - min > COST_EPS then
            local delta = r.widths[i] - w
            if math.abs(delta) > COST_EPS then
                local class
                if delta < 0 then
                    class = g.shrink_class or LAST_RESORT
                else
                    class = g.stretch_class or LAST_RESORT
                end
                local d = math.abs(delta)
                if prof[class] == nil then prof[class] = 0 end
                if d > prof[class] then prof[class] = d end
            end
        end
    end
    return prof, r
end

-- 词典序比较：从最后手段往前逐级比，先分出胜负的那一级说了算。
-- 全等时返回 0——由调用方按 clreq「先挤进，后推出」选挤进。
-- @return (number) <0 表示 a 更优，>0 表示 b 更优，0 表示等价
-- @return (string|nil) 分出胜负的类别
local function compare_profiles(a, b)
    for i = #COST_ORDER, 1, -1 do
        local class = COST_ORDER[i]
        local da, db = a[class] or 0, b[class] or 0
        if math.abs(da - db) > 1e-7 then
            return (da < db) and -1 or 1, class
        end
    end
    return 0, nil
end

--- Resolve a line/column overflow caused by a kinsoku violation: is it cheaper
-- to squeeze the offending character into the current line ("挤进") or to push
-- it out to the next one ("推出")?
--
-- Both candidates are solved with adjust.solve, so the comparison sees the real
-- clreq priority order: recovering a comma's blank costs far less than opening
-- up the inter-character spacing. A backend that compares raw gap sizes cannot
-- know this and will push out lines the solver could have absorbed.
--
-- 比较用词典序（见 candidate_profile 的说明），先看谁少动最后手段（字距），
-- 打平再往优先顺序前面看。clreq 的口径是「先挤进，后推出」，全等时选挤进。
--
-- @param cands (table) {
--   squeeze = { target = number, gaps = {...} },  -- 多收一个字的排布
--   stretch = { target = number, gaps = {...} },  -- 少一个字的排布
-- }  两者的 target 均为「gap 可用总量」= 列可用长度 − 该候选的刚性总量。
-- @return (string) "squeeze" | "stretch"
-- @return (table) {
--   squeeze_profile, stretch_profile,  -- class → 该类最大形变量（nil = 不可行）
--   squeeze_gap, stretch_gap,          -- 字距形变量，日志用的头条数字
--   decided_by,                        -- 分出胜负的类别（nil = 全等，按先挤进）
--   squeeze, stretch,                  -- adjust.solve 结果，可直接落盘
-- }
function M.resolve_overflow(cands)
    local sq_prof, sq_res, st_prof, st_res
    if cands.squeeze then
        sq_prof, sq_res = candidate_profile(cands.squeeze.target, cands.squeeze.gaps)
    end
    if cands.stretch then
        st_prof, st_res = candidate_profile(cands.stretch.target, cands.stretch.gaps)
    end
    local detail = {
        squeeze_profile = sq_prof, stretch_profile = st_prof,
        squeeze = sq_res, stretch = st_res,
        squeeze_gap = sq_prof and sq_prof[LAST_RESORT] or math.huge,
        stretch_gap = st_prof and st_prof[LAST_RESORT] or math.huge,
    }
    -- 不可行的候选直接出局；都不可行时按 clreq 选挤进（推出也放不下，
    -- 至少挤进不会多留一列空）
    if not sq_prof then
        return st_prof and "stretch" or "squeeze", detail
    end
    if not st_prof then return "squeeze", detail end

    local cmp, class = compare_profiles(sq_prof, st_prof)
    detail.decided_by = class
    if cmp > 0 then return "stretch", detail end
    return "squeeze", detail
end

--- For a run of `run_len` identical two-em members (dash/ellipsis), whether
-- a break after the `index`-th member (1-based) is allowed: clreq permits
-- breaking between complete pairs when more than one pair is present.
-- @param run_len (number) total members in the run
-- @param index (number) position of the character before the break candidate
-- @return (boolean) true if the pair rule may be lifted at this boundary
function M.pair_boundary_breakable(run_len, index)
    if run_len <= 2 then return false end
    return index % 2 == 0
end

return M
