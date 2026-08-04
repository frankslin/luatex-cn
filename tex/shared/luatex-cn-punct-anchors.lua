-- luatex-cn-punct-anchors.lua
-- clreq《标点符号的字面分布》的**度量锚点**（共享层）。
--
-- 中国大陆式：点号字面偏靠（横排左下、直排右上）；台湾式：字面居中。
-- 字体把墨迹画在字幅的哪个位置是字体自己的设计惯例（中国大陆字体横排形
-- 在左下、直排 vert 形在右上；台湾字体两个方向都居中）——排版风格
-- 不应随字体漂移。本模块给出每个标点在每种 style × mode 下墨迹中心
-- 应落的位置（em 比值，x 自左、y 自基线向上），后端读字形 boundingbox
-- 算出墨心，把差值写进 xoffset/yoffset：字体画在哪都无所谓，量出来
-- 再挪过去。
--
-- 锚点值取自该风格的样板字体实测（样板字体自身位移为零，其余字体
-- 收敛到同一落点）：
--   台湾式（横竖同值）：TW-Kai——横竖两个方向字形都居中；
--   中国大陆式横排：思源宋体（Source Han Serif SC）——GB 惯例左下；
--   中国大陆式直排：TW-Kai 在旧「经验偏移」实现下的实测落点（该观感已经
--   过基线评审）：墨心对中 + 0.2×格宽右移（cn-vbook 版式合 0.857em），
--   句号另 +0.25em 上移；中点类纵向取 TW-Kai 字形的自然位置。
--
-- 纯 Lua、零 TeX 依赖（HR5：clreq 规则只写在 tex/shared/）。
-- 契约见 ai_must_read/clreq-shared-core.md。

local M = {}

-- 键为**原始码位**（vert GSUB 落到 PUA 的字形由后端先解析回原始码位）。
-- 值 {x, y}：墨迹中心的目标位置（em）。y = nil 表示纵向随字形设计。

-- 台湾式（横排、直排同值）：字面居中。TW-Kai 实测。
local TAIWAN = {
    [0xFF0C] = { x = 0.495, y = 0.311 }, -- ，
    [0x3001] = { x = 0.478, y = 0.314 }, -- 、
    [0x3002] = { x = 0.499, y = 0.299 }, -- 。
    [0xFF0E] = { x = 0.499, y = 0.299 }, -- ．
    [0xFF1A] = { x = 0.500, y = 0.363 }, -- ：
    [0xFF1B] = { x = 0.496, y = 0.313 }, -- ；
    [0xFF01] = { x = 0.496, y = 0.316 }, -- ！
    [0xFF1F] = { x = 0.500, y = 0.320 }, -- ？
}

-- 中国大陆式横排：点号靠左下（GB 惯例）。思源宋体实测。
local HORI_MAINLAND = {
    [0xFF0C] = { x = 0.153, y = -0.039 },
    [0x3001] = { x = 0.165, y = 0.049 },
    [0x3002] = { x = 0.183, y = 0.059 },
    [0xFF0E] = { x = 0.183, y = 0.059 },
    [0xFF1A] = { x = 0.232, y = 0.296 },
    [0xFF1B] = { x = 0.214, y = 0.217 },
    [0xFF01] = { x = 0.249, y = 0.390 },
    [0xFF1F] = { x = 0.247, y = 0.377 },
}

-- 中国大陆式直排：点号偏靠右上（贴前字）。x=0.857 见文件头；中点类
-- （：；！？）保持直立，横向偏靠、纵向取 TW-Kai 的自然位置。
local VERT_MAINLAND = {
    [0xFF0C] = { x = 0.857, y = 0.31 },
    [0x3001] = { x = 0.857, y = 0.31 },
    [0x3002] = { x = 0.857, y = 0.55 },
    [0xFF0E] = { x = 0.857, y = 0.55 },
    [0xFF1A] = { x = 0.857, y = 0.363 },
    [0xFF1B] = { x = 0.857, y = 0.313 },
    [0xFF01] = { x = 0.857, y = 0.316 },
    [0xFF1F] = { x = 0.857, y = 0.320 },
}

--- 查锚点。
-- @param orig (number) 原始码位（PUA vert 形须先解析回来）
-- @param style (string) "mainland" | "taiwan" | "none"
-- @param mode (string) "horizontal" | "vertical"
-- @return (table|nil) { x, y } em；style="none" 或无此码位时 nil
function M.anchor(orig, style, mode)
    if style == "taiwan" then
        return TAIWAN[orig]
    elseif style == "mainland" then
        if mode == "horizontal" then
            return HORI_MAINLAND[orig]
        end
        return VERT_MAINLAND[orig]
    end
    return nil -- "none"：不调整预设，字面不挪动
end

--- 把墨迹中心挪到锚点所需的位移（纯函数，便于单测）。
-- @param orig (number) 原始码位
-- @param style (string) "mainland" | "taiwan" | "none"
-- @param mode (string) "horizontal" | "vertical"
-- @param bb (table) 字形 boundingbox {xmin, ymin, xmax, ymax}（字体单位）
-- @param upem (number) 字体 units_per_em
-- @param em_sp (number) 该字形自身字号（sp）
-- @return (number|nil, number) dx, dy（sp）；无锚点或数据不全时 nil
function M.offsets(orig, style, mode, bb, upem, em_sp)
    local a = M.anchor(orig, style, mode)
    if not a or not bb or not upem or upem <= 0 or not em_sp then
        return nil, 0
    end
    if not (bb[1] and bb[3]) then return nil, 0 end
    -- 死区：锚点值是样板字体的实测（3 位小数），与该字体自身墨心的
    -- 残差在 0.001em 量级。低于视觉阈值的位移一律取零——样板字体因此
    -- 严格零位移（版面 bit 不变），也避免亚可视的 yoffset 干扰按坐标
    -- 分行/分列的度量工具。
    local EPS = 0.002
    local function shift(target, center)
        local d = target - center
        if math.abs(d) < EPS then return 0 end
        return math.floor(d * em_sp + 0.5)
    end
    local dx = shift(a.x, (bb[1] + bb[3]) / 2 / upem)
    local dy = 0
    if a.y and bb[2] and bb[4] then
        dy = shift(a.y, (bb[2] + bb[4]) / 2 / upem)
    end
    return dx, dy
end

return M
