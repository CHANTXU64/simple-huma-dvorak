-- omit_fix.lua —— 只敲了"一简字"的那一个键就走了，自动补上它的第二键，把对应的常用词放到第一位
--
-- 虎码里 26 个键各有一个"一简字"（u=一、y=我、g=的……），敲一个键就能出。手快的时候，
-- 打 2 字词时会只敲一简字的那一个键，漏掉它本该有的第二键：
--   想打 一个(uchi)，"一"是 u 的一简字，只敲了 u，结果成了 uhi（漏了 c）。
--   uhi 不是任何词的码，候选只有编码提示（补全）列出来的 一人善射，百夫决拾(uhig，权重 48) 之类，
--   实际要的 一个(权重 105148) 不在其中。这里把漏掉的键补回去，一个(uchi)放到第一位（注释 ⊕）。
--
-- 触发条件（全部满足才改顺序，其余输入的顺序完全不动）：
--   * 开关 omit_fix 打开（Rime 菜单里切换，默认开）
--   * 输入正好 3 码，且这个 3 码没有任何精确词条：词典里的正式 3 码（简码词、3 码单字）一律不动
--   * 补上的键只能是"第 1 个字的第 2 键"（插在第 1 键后）或"第 2 个字的第 2 键"（补在末尾），
--     补出的是 2 字词，且漏键的那个字恰好是它第一键的一简字（没有这个条件就不补：
--     比如 眼 不是 ' 的一简字，那就不会因为漏了 c 就把 'c'a 眼睛 顶上来）
--   * 判断规则与 swap_fix 完全相同（权重上限、随词频浮动的倍数、词的最低权重），
--     只是"实际敲出的第一候选"取的是补全候选里权重最高的一个
-- 不学习；出任何错都只会退化成原样输出。参数在方案的 omit_fix: 下，含义同 swap_fix:。
--
-- 接入：rime.lua 里加   omit_fix = require("omit_fix").F
--       方案 switches 里加开关 omit_fix，engine/filters 里（uniquifier 之前）加   - lua_filter@omit_fix

local S = require("swap_fix")._M

local CODE_LEN = 3 -- 只处理敲了几码的输入（补一个键后是 4 码）
-- 编码用到的键；w、v 是自动上屏键，从不出现在词码里
local ALPHABET = ";,.'yxutrqponmlkjihgfedcbaw"

local M = {}

-- ---------- 纯函数（不依赖 Rime，可单独测试）----------

-- 返回所有可能的补键方案 { {code=补键后的 4 码, pos=补出的键在第几位(2 或 4), key=该字的第一键}, ... }
function M.slots(code, alphabet)
  local out = {}
  for k = 1, #alphabet do
    local ch = alphabet:sub(k, k)
    out[#out + 1] = { code = code:sub(1, 1) .. ch .. code:sub(2), pos = 2, key = code:sub(1, 1) }
    out[#out + 1] = { code = code .. ch, pos = 4, key = code:sub(3, 3) }
  end
  return out
end

-- 词的第 n 个字（UTF-8），不存在返回 nil
function M.char_at(text, n)
  local a = utf8.offset(text, n)
  local b = utf8.offset(text, n + 1)
  if not a or not b then return nil end
  return text:sub(a, b - 1)
end

-- ---------- Rime 接入 ----------

local F = {}

function F.init(env)
  local ok, mem = pcall(Memory, env.engine, env.engine.schema, "translator")
  if ok then
    env.mem = mem
  else
    log.warning("omit_fix: Memory init failed: " .. tostring(mem))
  end
  env.cfg = S.load_cfg(env, "omit_fix")
  env.one = {} -- 缓存：键 -> 一简字（false 表示没有）
end

function F.fini(env)
  env.mem = nil
end

-- 某个键的一简字
local function one_char(env, key)
  local c = env.one[key]
  if c == nil then
    local e = S.top_entry(env.mem, key, false)
    c = (e and utf8.len(e.text) == 1) and e.text or false
    env.one[key] = c
  end
  return c or nil
end

-- 最佳补键方案：{text=, weight=}, 补键后的码；没有则 nil
local function best_insert(env, code)
  local best, best_code
  for _, slot in ipairs(M.slots(code, ALPHABET)) do
    local one = one_char(env, slot.key)
    if one then
      for _, e in ipairs(S.entries(env.mem, slot.code, false)) do
        local ch = utf8.len(e.text) == 2 and M.char_at(e.text, slot.pos / 2)
        if ch == one and (not best or e.weight > best.weight) then best, best_code = e, slot.code end
      end
    end
  end
  return best, best_code
end

local function promoted(env)
  local ctx = env.engine.context
  if not ctx:get_option("omit_fix") then return nil end
  local code = ctx.input
  if #code ~= CODE_LEN or not env.mem then return nil end
  local seg = ctx.composition:back()
  if not seg then return nil end
  -- 正式的 3 码（简码词、3 码单字）不动
  if S.top_entry(env.mem, code, false) then return nil end
  -- 实际看到的候选都是补全，取其中权重最高的
  local typed = S.top_entry(env.mem, code, true)
  local best, best_code = best_insert(env, code)
  if not S.should_swap(typed, best, env.cfg) then return nil end
  log.info(string.format("omit_fix: %s(%s %.0f) -> %s(%s %.0f)", code,
    typed and typed.text or "-", typed and typed.weight or 0, best_code, best.text, best.weight))
  pcall(function()
    require("typing_log").event(env, { e = "omit_fix", code = code, from = typed and typed.text or nil, to = best.text })
  end)
  return Candidate("omit_fix", seg.start, seg._end, best.text, "⊕")
end

function F.func(input, env)
  local ok, cand = pcall(promoted, env)
  if ok and cand then yield(cand) end
  if not ok then log.warning("omit_fix: " .. tostring(cand)) end
  for c in input:iter() do yield(c) end
end

return { F = F, _M = M }
