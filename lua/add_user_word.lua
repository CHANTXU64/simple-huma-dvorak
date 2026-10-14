-- add_user_word.lua —— 先分段上屏，再敲整词码，选中即自动加词（无快捷键）
--
-- 用法：想加"社会主义"时，先照常打 社会、主义 并上屏；
--       然后敲整词码 uhcc。插件回看最近最多 4 条上屏记录，把末尾若干条拼起来，
--       按虎码规则算码，码与你敲的完全一致的，就作为候选放在【最后】（注释 +）。
--       选中它 -> 写入 user_words.tsv，以后敲 uhcc 在候选最后出（注释 *）；选了别的候选 -> 什么都不记。
--
-- 特点：
--   * 词存在 <Rime 用户目录>/user_words.tsv（每行 词<Tab>编码），不进 git，想删直接改这个文件
--   * 编码按 encoder.rules 自动算；静态词条：不学习；所有加进来的候选都排在最后，不影响正常输入
--   * 出任何错都只会退化成原样输出，不会影响正常打字
--   * 不依赖 enable_user_dict / enable_sentence，也不需要重新部署
--   * 只要求连续的汉字上屏记录：中间夹了标点、空格、字母等就不算连续
--
-- 接入：rime.lua 里加   add_user_word = require("add_user_word").F
--       方案 engine/filters 里（uniquifier 之前）加   - lua_filter@add_user_word


local MAX_BACK = 4 -- 最多回看最近多少条上屏记录

local M = {}

-- ---------- 纯函数（不依赖 Rime，可单独测试）----------

-- 文本是否全部是汉字
function M.is_cjk(s)
  if s == nil or s == "" or not utf8.len(s) then return false end
  for _, c in utf8.codes(s) do
    local ok = (c >= 0x3400 and c <= 0x4dbf) or (c >= 0x4e00 and c <= 0x9fff)
      or (c >= 0x20000 and c <= 0x323af) or (c >= 0xf900 and c <= 0xfaff)
    if not ok then return false end
  end
  return true
end

local function nth_char(word, i)
  return word:sub(utf8.offset(word, i), utf8.offset(word, i + 1) - 1)
end

-- 与 tigress.extended.dict.yaml 的 encoder.rules 保持一致：
--   2 字 AaAbBaBb；3 字 AaBaCaCb；4 字及以上 AaBaCaZa
-- 一个字有多个编码时（权重 >= 该字总权重的 5%），Rime 会把各种组合都造出来，这里同样。
local function encode_one(c, n)
  if n == 2 then
    return c[1]:sub(1, 2) .. c[2]:sub(1, 2)
  elseif n == 3 then
    return c[1]:sub(1, 1) .. c[2]:sub(1, 1) .. c[3]:sub(1, 2)
  end
  return c[1]:sub(1, 1) .. c[2]:sub(1, 1) .. c[3]:sub(1, 1) .. c[n]:sub(1, 1)
end

-- codes: { [字] = {编码, ...} }；返回去重后的编码列表，算不出来返回 nil
function M.encode(word, codes)
  local n = utf8.len(word)
  if n < 2 then return nil end
  local lists = {}
  for i = 1, n do
    lists[i] = codes[nth_char(word, i)]
    if not lists[i] then return nil end
  end
  local out, seen = {}, {}
  local pick = {}
  local function walk(i)
    if i > n then
      local ok, code = pcall(encode_one, pick, n)
      if ok and #code == 4 and not seen[code] then
        seen[code] = true
        out[#out + 1] = code
      end
      return
    end
    for _, c in ipairs(lists[i]) do
      pick[i] = c; walk(i + 1)
    end
  end
  walk(1)
  if #out == 0 then return nil end
  return out
end

-- 读取单字码表（tigress.dict.yaml），每字保留权重 >= 总权重 5% 的编码
function M.load_char_codes(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local cols, in_body, in_cols = {}, false, false
  local all = {}
  for line in f:lines() do
    if not in_body then
      if line:match("^columns:") then
        in_cols = true
      elseif in_cols and line:match("^%s*%- ") then
        cols[#cols + 1] = line:match("^%s*%- (%S+)")
      elseif line == "..." then
        in_body = true
      end
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      local p = {}
      for field in (line .. "\t"):gmatch("([^\t]*)\t") do p[#p + 1] = field end
      local d = {}
      for i, name in ipairs(cols) do d[name] = p[i] end
      if d.text and d.code and utf8.len(d.text) == 1 then
        local t = all[d.text] or { total = 0, items = {} }
        local w = tonumber(d.weight) or 0
        t.total = t.total + w
        t.items[#t.items + 1] = { d.code, w }
        all[d.text] = t
      end
    end
  end
  f:close()
  local codes = {}
  for ch, t in pairs(all) do
    local list = {}
    for _, it in ipairs(t.items) do
      if it[2] >= t.total * 0.05 then list[#list + 1] = it[1] end
    end
    if #list == 0 then list[1] = t.items[1][1] end
    codes[ch] = list
  end
  return codes
end

-- 读取 user_words.tsv，返回 { [编码] = {词, ...} }
function M.load_words(path)
  local by_code = {}
  local f = io.open(path, "r")
  if not f then return by_code end
  for line in f:lines() do
    local word, code = line:match("^([^\t]+)\t([^\t]+)")
    if word then
      by_code[code] = by_code[code] or {}
      table.insert(by_code[code], word)
    end
  end
  f:close()
  return by_code
end

local function read_all(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local rows = {}
  for line in f:lines() do rows[#rows + 1] = line end
  f:close()
  return rows
end

function M.add_word(path, word, code)
  for _, line in ipairs(read_all(path)) do
    if line == word .. "\t" .. code then return false end -- 已存在
  end
  local f = assert(io.open(path, "a"))
  f:write(word, "\t", code, "\n")
  f:close()
  return true
end

function M.remove_word(path, word)
  local kept, removed = {}, false
  for _, line in ipairs(read_all(path)) do
    if line:match("^([^\t]+)") == word then removed = true else kept[#kept + 1] = line end
  end
  if removed then
    local f = assert(io.open(path, "w"))
    if #kept > 0 then f:write(table.concat(kept, "\n"), "\n") end
    f:close()
  end
  return removed
end

-- records: 最近的上屏文本，新 -> 旧。从最新一条往前累加，遇到非汉字（标点/空格/字母）就停，
-- 最多 max_back 条。对每个"末尾 k 条的拼接"算码，码等于 input 的就收下。
-- 返回 { {word=..., k=...}, ... }，k 小的在前。
function M.match_suffixes(records, input, codes, max_back)
  local out, tail = {}, ""
  for k = 1, math.min(#records, max_back) do
    local t = records[k]
    if not M.is_cjk(t) then break end
    tail = t .. tail
    if utf8.len(tail) >= 2 then
      for _, c in ipairs(M.encode(tail, codes) or {}) do
        if c == input then out[#out + 1] = { word = tail, k = k }; break end
      end
    end
  end
  return out
end

-- ---------- Rime 接入 ----------

local function user_dir() return rime_api.get_user_data_dir() end
local function words_path() return user_dir() .. "/user_words.tsv" end

-- 单字码表：进程级缓存。读一遍 tigress.dict.yaml 要 ~100ms，缓存若挂在输入会话上，
-- 每新开一个会话（重启 Squirrel、切到新应用）第一次敲满 4 码都要卡一下
local char_codes_cache
local function get_char_codes()
  if not char_codes_cache then
    char_codes_cache = M.load_char_codes(user_dir() .. "/tigress.dict.yaml")
  end
  return char_codes_cache
end

local F = {}

-- 当前菜单里"待确认"的候选：{ [词] = 编码 }，选中时据此判断是否要加词
local pending = {}

function F.init(env)
  pcall(function()
    env.conn = env.engine.context.commit_notifier:connect(function(c)
      local ok, err = pcall(function()
        local text = c:get_commit_text()
        local code = pending[text]
        if code then
          pending = {}
          M.add_word(words_path(), text, code)
        end
      end)
      if not ok then log.warning("add_user_word commit: " .. tostring(err)) end
    end)
  end)
end

function F.fini(env)
  pcall(function() if env.conn then env.conn:disconnect() end end)
end

-- 算出要追加在最后的候选：{ {text=, type=, comment=}, ... }
local function extra_candidates(ctx, env)
  local code = ctx.input
  pending = {}
  local out = {}
  for _, w in ipairs(M.load_words(words_path())[code] or {}) do
    out[#out + 1] = { text = w, type = "user_word", comment = "*" }
  end
  -- 整词码一律是 4 位；不是 4 位的输入不用查历史
  if #code == 4 then
    local records = {}
    for _, cr in ctx.commit_history:iter() do
      records[#records + 1] = cr.text
      if #records >= MAX_BACK then break end
    end
    if #records > 0 then
      local char_codes = get_char_codes()
      if char_codes then
        for _, m in ipairs(M.match_suffixes(records, code, char_codes, MAX_BACK)) do
          pending[m.word] = code
          out[#out + 1] = { text = m.word, type = "user_word_pending", comment = "+" }
        end
      end
    end
  end
  return out
end

function F.func(input, env)
  local seen = {}
  for cand in input:iter() do
    seen[cand.text] = true
    yield(cand)
  end
  -- 原有候选全部输出完之后，才追加自造词；这里任何出错都不影响上面已经输出的候选
  pcall(function()
    local ctx = env.engine.context
    local seg = ctx.composition:back()
    if not seg then return end
    for _, e in ipairs(extra_candidates(ctx, env)) do
      if not seen[e.text] then
        seen[e.text] = true
        yield(Candidate(e.type, seg.start, seg._end, e.text, e.comment))
      end
    end
  end)
end

-- 模块加载时就读好（Squirrel 启动或部署时），敲字时不用再等；失败了就留给第一次用到时再试
pcall(get_char_codes)

return { F = F, _M = M }
