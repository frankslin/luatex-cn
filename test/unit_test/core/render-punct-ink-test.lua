-- Unit tests for punct_ink_placement (core.luatex-cn-core-render-page-process)
--
-- clreq 《标点符号的宽度调整》规定字面空白有确定的一侧：中国大陆式点号在末端、
-- 开始夹注符号在始端。收回哪一侧，字面就往哪边让——所以缩短的字幅只用于
-- 列内排版算术，定位必须按原始满幅进行、再按始端收回量上移。
-- 回归对象：若把收回量当作对称缩短，居中逻辑会让句号向上飘半个收回量、
-- 紧贴前一个字（PR #132 评审发现的缺陷）。
local test_utils = require("test.test_utils")
local process = require("core.luatex-cn-core-render-page-process")
local place = process.punct_ink_placement

local EM = 655360          -- 10pt
local FULL = EM            -- 满幅
local Y = 100 * 65536

test_utils.run_test("未参与上下文挤压的字形原样返回", function()
    local h, y = place(FULL, Y, nil, nil, EM)
    test_utils.assert_eq(h, FULL)
    test_utils.assert_eq(y, Y)
    -- 属性为 1 表示「收回 0」，同样不动
    h, y = place(FULL, Y, 1, 1, EM)
    test_utils.assert_eq(h, FULL)
    test_utils.assert_eq(y, Y)
end)

test_utils.run_test("收回末端空白：定位用满幅、起点不动（字面原地不动）", function()
    -- 中国大陆式句号紧邻结束夹注符号：收回末端 0.5 em，始端 0
    local shrunk = FULL // 2
    local h, y = place(shrunk, Y, 501, 1, EM)
    test_utils.assert_eq(h, shrunk + 0.5 * EM, "定位应按原始满幅")
    test_utils.assert_eq(y, Y, "末端收回不得移动字面")
end)

test_utils.run_test("收回始端空白：起点上移收回量（字面向后贴紧）", function()
    -- 行内开始夹注符号紧跟冒号：收回始端 0.5 em
    local shrunk = FULL // 2
    local h, y = place(shrunk, Y, 501, 501, EM)
    test_utils.assert_eq(h, shrunk + 0.5 * EM)
    test_utils.assert_eq(y, Y - 0.5 * EM, "始端收回应让字面向后贴紧被夹注内容")
end)

test_utils.run_test("两端各收回一半（台式点号）：起点只上移始端那一半", function()
    local shrunk = FULL // 2
    local h, y = place(shrunk, Y, 501, 251, EM)
    test_utils.assert_eq(h, shrunk + 0.5 * EM)
    test_utils.assert_eq(y, Y - 0.25 * EM)
end)

test_utils.run_test("相邻缩减的分摊量（0.25 em）", function()
    local shrunk = FULL - 0.25 * EM
    local h, y = place(shrunk, Y, 251, 1, EM)
    test_utils.assert_eq(h, FULL)
    test_utils.assert_eq(y, Y)
end)

test_utils.run_test("缺字号或字幅时不做任何调整（防御）", function()
    local h, y = place(FULL, Y, 501, 501, nil)
    test_utils.assert_eq(h, FULL)
    test_utils.assert_eq(y, Y)
    h, y = place(nil, Y, 501, 501, EM)
    test_utils.assert_nil(h)
    test_utils.assert_eq(y, Y)
end)
