-- swap_fix.lua —— 左右手按快了、相邻两键顺序颠倒时，自动把"对调后的词"放到第一位
--
-- 例：想打 提交(grax)，右手无名指(r)和左手小拇指(a)抢拍，打成了 garx -> 白癜风。
--     garx 的第一候选 白癜风(权重 371) 比 对调后 grax 的 提交(权重 4532) 冷门得多，
--     于是直接把 提交 排到第一位（注释 ↔），不用你去看候选。
--
-- 触发条件（全部满足才改顺序，其余输入的顺序完全不动）：
--   * 开关 swap_fix 打开（Rime 菜单里切换，默认开）
--   * 输入正好 4 码
--   * 只对调【左右手交替】的相邻两键（Dvorak 布局），且不动第 1 键（一个词一个词打，第一键不会错）
--   * 对调后的第一候选是词（>= 2 字），权重不低于 min_target_weight
--   * 实际敲出的第一候选是词（或根本没有候选）；是单字的话不动，免得把敲对的生僻字换掉
--   * 实际敲出的词权重不超过 max_typed_weight：比较常用的词（如 这句）绝不会被顶掉
--   * 对调后的词要比实际敲出的词常用 N 倍以上，N 随被顶掉的词浮动：
--       词越冷门（越像凑数的词）N 越小，越接近 max_typed_weight N 越大，
--       权重 <= low_weight 时 N = ratio_low，权重 = max_typed_weight 时 N = ratio_high，之间按对数插值
-- 不学习、不记录任何东西；出任何错都只会退化成原样输出。
--
-- 参数（可选，写在方案的 swap_fix: 下，缺省值见下面的 DEFAULTS）
--
-- 接入：rime.lua 里加   swap_fix = require("swap_fix").F
--       方案 switches 里加开关 swap_fix，engine/filters 里（uniquifier 之前）加   - lua_filter@swap_fix

local CODE_LEN = 4 -- 只处理满几码的输入

local DEFAULTS = {
  max_typed_weight = 400,  -- 被顶掉的词权重上限（词典里的原始权重）
  low_weight = 60,         -- 权重不超过它的词算"凑数的词"
  ratio_low = 3,           -- 凑数的词：对调后的词只要常用 3 倍以上就纠正
  ratio_high = 10,         -- 权重到上限的词：要常用 10 倍以上才纠正
  min_target_weight = 500, -- 对调后的词本身至少要有这么常用
}

-- librime 把词条权重存成 ln(原始权重) + ln(1e-8)（实测：白癜风 371 -> -12.5045）
local LOG_OFFSET = math.log(1e-8)

local M = {}

-- ---------- 纯函数（不依赖 Rime，可单独测试）----------

-- Dvorak 下各键归哪只手（码表里的字母就是 Dvorak 键面上的字母）
local LEFT = "',.pyaoeui;qjkx"
local RIGHT = "fgcrldhtnsbmwvz"

local hand = {}
for c in LEFT:gmatch(".") do hand[c] = "L" end
for c in RIGHT:gmatch(".") do hand[c] = "R" end

-- 返回 { 对调后的码, ... }：只含左右手交替的相邻键，去重，不含原码；第 1 键不动
function M.swaps(code)
  local out, seen = {}, { [code] = true }
  for i = 2, #code - 1 do
    local a, b = code:sub(i, i), code:sub(i + 1, i + 1)
    if hand[a] and hand[b] and hand[a] ~= hand[b] then
      local swapped = code:sub(1, i - 1) .. b .. a .. code:sub(i + 2)
      if not seen[swapped] then
        seen[swapped] = true
        out[#out + 1] = swapped
      end
    end
  end
  return out
end

local function is_word(text) return (utf8.len(text) or 0) >= 2 end

-- 被顶掉的词权重为 w 时，对调后的词至少要常用多少倍
function M.required_ratio(w, cfg)
  if w <= cfg.low_weight then return cfg.ratio_low end
  if w >= cfg.max_typed_weight then return cfg.ratio_high end
  local x = (math.log(w) - math.log(cfg.low_weight))
    / (math.log(cfg.max_typed_weight) - math.log(cfg.low_weight))
  return cfg.ratio_low + (cfg.ratio_high - cfg.ratio_low) * x
end

-- typed / best：{text=, weight=} 或 nil；weight 是原始权重（线性）
-- 该不该用 best 顶掉 typed 的第一位
function M.should_swap(typed, best, cfg)
  if not best or not is_word(best.text) then return false end
  if best.weight < cfg.min_target_weight then return false end
  if not typed then return true end
  if not is_word(typed.text) then return false end
  if typed.weight > cfg.max_typed_weight then return false end
  return best.weight > typed.weight * M.required_ratio(typed.weight, cfg)
end

-- ---------- Rime 接入 ----------

-- 查某个码，返回所有词条 { {text=, weight=原始权重}, ... }；
-- predictive 为 true 时连补全（以它开头的更长的码）一起查
function M.entries(mem, code, predictive)
  local out = {}
  if mem:dict_lookup(code, predictive or false, predictive and 300 or 50) then
    for entry in mem:iter_dict() do
      out[#out + 1] = { text = entry.text, weight = math.exp(entry.weight - LOG_OFFSET) }
    end
  end
  return out
end

-- 同上，只返回权重最高的一条，没有则 nil
function M.top_entry(mem, code, predictive)
  local best
  for _, e in ipairs(M.entries(mem, code, predictive)) do
    if not best or e.weight > best.weight then best = e end
  end
  return best
end

-- 读方案里 <ns>/ 下的参数，缺省用 DEFAULTS
function M.load_cfg(env, ns)
  local cfg = {}
  for k, v in pairs(DEFAULTS) do
    local ok, val = pcall(function() return env.engine.schema.config:get_double(ns .. "/" .. k) end)
    cfg[k] = (ok and val and val > 0) and val or v
  end
  return cfg
end


local F = {}

function F.init(env)
  -- 复用方案里 translator 的词典，只做精确查码
  local ok, mem = pcall(Memory, env.engine, env.engine.schema, "translator")
  if ok then
    env.mem = mem
  else
    log.warning("swap_fix: Memory init failed: " .. tostring(mem))
  end
  env.cfg = M.load_cfg(env, "swap_fix")
end

function F.fini(env)
  env.mem = nil
end

-- 算出要提到最前面的候选；不需要则返回 nil
local function promoted(env)
  local ctx = env.engine.context
  if not ctx:get_option("swap_fix") then return nil end
  local code = ctx.input
  if #code ~= CODE_LEN or not env.mem then return nil end
  local seg = ctx.composition:back()
  if not seg then return nil end
  local typed = M.top_entry(env.mem, code)
  local best, best_code
  for _, sc in ipairs(M.swaps(code)) do
    local e = M.top_entry(env.mem, sc)
    if e and (not best or e.weight > best.weight) then best, best_code = e, sc end
  end
  if not M.should_swap(typed, best, env.cfg) then return nil end
  log.info(string.format("swap_fix: %s(%s %.0f) -> %s(%s %.0f)", code,
    typed and typed.text or "-", typed and typed.weight or 0, best_code, best.text, best.weight))
  pcall(function()
    require("typing_log").event(env, { e = "swap_fix", code = code, from = typed and typed.text or nil, to = best.text })
  end)
  return Candidate("swap_fix", seg.start, seg._end, best.text, "↔")
end

function F.func(input, env)
  local ok, cand = pcall(promoted, env)
  if ok and cand then yield(cand) end
  if not ok then log.warning("swap_fix: " .. tostring(cand)) end
  for c in input:iter() do yield(c) end
end

return { F = F, _M = M, DEFAULTS = DEFAULTS }
