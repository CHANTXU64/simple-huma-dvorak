-- typing_log.lua —— 把输入过程记成本地日志，供事后分析（比如 提交 打成 白癜风 又删掉重打）
--
-- 记什么（每行一个 JSON，写到 <Rime 用户目录>/typing_log.YYYY-MM-DD.jsonl，只在本机，不进 git）：
--   {"ts":时间戳,"e":"commit","text":上屏的词,"code":当时敲的码,"idx":选的第几个候选(从0数)}
--   {"ts":..,"e":"bs","composing":false}              敲码之外按的退格（多半是在删刚上屏的字）
--   {"ts":..,"e":"bs","composing":true,"code":"gar"}   敲码过程中的退格，code 是退格【之前】的码
--   {"ts":..,"e":"cancel","code":"garx"}              敲了码按 Esc 取消
--   {"ts":..,"e":"swap_fix","code":..,"from":..,"to":..}  swap_fix 自动纠正了一次
--
-- （Squirrel 1.1.2 里取不到当前应用，client_app 属性是空的，所以没有 app 字段；
--   哪天取得到了，event() 会自动带上 app。）
-- 不记什么：西文模式下的按键一律不记；开关 typing_log 关掉后什么都不写。
-- 做不到的：Rime 看不到应用里的文本，所以鼠标选中删除、Cmd+Delete 这类删除记不到，
--           只能看到"按了 Backspace"。分析脚本 tools/typing_log_report.py 靠
--           "上屏 -> 若干退格 -> 再上屏" 的序列还原纠错。
-- 日志文件创建时权限设为 0200（只写，属主也不能读），不会过期；想清空直接删 typing_log.*.jsonl。
-- 要分析时先 chmod u+r typing_log.*.jsonl，看完再 chmod u-r（或 chmod 200）。
--
-- 接入：rime.lua 里加   typing_log = require("typing_log").P
--       方案 engine/processors 里放在【最前面】（否则退格被编辑器吃掉就看不到了）：- lua_processor@typing_log
--       方案 switches 里加开关 typing_log

local K_NOOP = 2
local XK_BACKSPACE, XK_ESCAPE = 0xff08, 0xff1b

local M = {}

-- ---------- 纯函数（不依赖 Rime，可单独测试）----------

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
function M.json_str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function json_val(v)
  local t = type(v)
  if t == "string" then return M.json_str(v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  return "null"
end

-- ev 是 { key = 值 }；ts、e 固定排在最前，其余按键名排序，保证输出稳定
function M.encode(ev)
  local keys = {}
  for k in pairs(ev) do
    if k ~= "ts" and k ~= "e" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs({ "ts", "e" }) do
    if ev[k] ~= nil then parts[#parts + 1] = M.json_str(k) .. ":" .. json_val(ev[k]) end
  end
  for _, k in ipairs(keys) do
    if ev[k] ~= nil then parts[#parts + 1] = M.json_str(k) .. ":" .. json_val(ev[k]) end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- ---------- Rime 接入 ----------

local function log_path(day) return rime_api.get_user_data_dir() .. "/typing_log." .. day .. ".jsonl" end

-- 该不该记：开关开着，且不在西文模式
local function enabled(ctx)
  return ctx:get_option("typing_log") and not ctx:get_option("ascii_mode")
end

-- 写一条事件。出任何错都吞掉，绝不影响输入
function M.event(env, ev)
  pcall(function()
    local ctx = env.engine.context
    if not enabled(ctx) then return end
    ev.ts = os.time()
    local app = ctx:get_property("client_app")
    if app and app ~= "" then ev.app = app end
    local path = log_path(os.date("%Y-%m-%d", ev.ts))
    -- 只写文件读不了，用 rename 到自己来判断它存不存在（不需要读权限）
    local existed = os.rename(path, path)
    local f = io.open(path, "a")
    if not f then return end
    f:write(M.encode(ev), "\n")
    f:close()
    if not existed then os.execute('chmod 200 "' .. path .. '"') end
  end)
end

local P = {}

function P.init(env)
  pcall(function()
    env.conn = env.engine.context.commit_notifier:connect(function(ctx)
      local ok, err = pcall(function()
        local seg = ctx.composition:back()
        M.event(env, {
          e = "commit",
          text = ctx:get_commit_text(),
          code = ctx.input,
          idx = seg and seg.selected_index or nil,
        })
      end)
      if not ok then log.warning("typing_log commit: " .. tostring(err)) end
    end)
  end)
end

function P.fini(env)
  pcall(function() if env.conn then env.conn:disconnect() end end)
end

-- 只看不拦：永远返回 noop，让后面的处理器照常处理按键
function P.func(key, env)
  pcall(function()
    if key:release() then return end
    local kc = key.keycode
    if kc ~= XK_BACKSPACE and kc ~= XK_ESCAPE then return end
    local ctx = env.engine.context
    if not enabled(ctx) then return end
    local composing = ctx:is_composing()
    if kc == XK_BACKSPACE then
      local ev = { e = "bs", composing = composing }
      if composing then ev.code = ctx.input end
      if key:ctrl() or key:alt() or key:super() then ev.mod = true end
      M.event(env, ev)
    elseif composing then
      M.event(env, { e = "cancel", code = ctx.input })
    end
  end)
  return K_NOOP
end

return { P = P, event = M.event, _M = M }
