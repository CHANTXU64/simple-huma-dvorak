core2022 = require("core2022_filter") --自定义字符集过滤（常用字集）

add_user_word = require("add_user_word").F --分段上屏后敲整词码，选中即自动加词

ascii_toggle = require("ascii_toggle").P --Ctrl+Space 切换中/西文，敲到一半先上屏已敲的字母

swap_fix = require("swap_fix").F --左右手按快了颠倒相邻两键，自动把对调后更常用的词放到第一位（有开关）

typing_log = require("typing_log").P --输入过程记成本地日志（有开关），供分析用

omit_fix = require("omit_fix").F --只敲了一简字那一个键、漏了第二键，自动补上并把常用词放到第一位（有开关）
