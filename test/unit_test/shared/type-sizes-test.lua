-- Unit tests for shared.luatex-cn-type-sizes（号数制字号表，H5）
local test_utils = require("test.test_utils")
local sizes = require("shared.luatex-cn-type-sizes")

test_utils.run_test("canonical sizes (bp)", function()
    test_utils.assert_eq(sizes.size_of("初号"), 42)
    test_utils.assert_eq(sizes.size_of("一号"), 26)
    test_utils.assert_eq(sizes.size_of("三号"), 16)
    test_utils.assert_eq(sizes.size_of("四号"), 14)
    test_utils.assert_eq(sizes.size_of("小四"), 12)
    test_utils.assert_eq(sizes.size_of("五号"), 10.5)
    test_utils.assert_eq(sizes.size_of("小五"), 9)
    test_utils.assert_eq(sizes.size_of("八号"), 5)
end)

test_utils.run_test("unknown name returns nil", function()
    test_utils.assert_nil(sizes.size_of("九号"))
    test_utils.assert_nil(sizes.size_of(""))
end)

test_utils.run_test("default leading multiplier", function()
    test_utils.assert_eq(sizes.DEFAULT_LEADING, 1.5)
end)

test_utils.run_test("size ordering is monotone (号数越大字越小)", function()
    local order = { "初号", "小初", "一号", "小一", "二号", "小二", "三号",
                    "小三", "四号", "小四", "五号", "小五", "六号", "小六",
                    "七号", "八号" }
    for i = 2, #order do
        test_utils.assert_true(
            sizes.size_of(order[i]) < sizes.size_of(order[i - 1]),
            order[i] .. " 应小于 " .. order[i - 1])
    end
end)

print("All type-sizes tests passed.")
