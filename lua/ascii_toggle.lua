-- ascii_toggle.lua —— Ctrl+Space 切换中/西文，敲到一半时先把已敲的字母原样上屏
--
-- 为什么不用 key_binder 的 toggle: ascii_mode：它只翻转开关，候选框里敲了一半的字母还留着。
-- 这里的行为与右 Shift（commit_code）一致：
--   * 正在输入：把已敲的编码原样上屏，清空候选框，再切换中/西文
--   * 没在输入：只切换
--
-- Karabiner 把 Ctrl+Space 改成 Ctrl+右Option+Space，所以匹配的是 Control+Alt+space。
-- 出任何错都只会放行按键（交给 schema 里 key_binder 的同一组合键兜底）。
--
-- 接入：rime.lua 里加   ascii_toggle = require("ascii_toggle").P
--       方案 engine/processors 里（ascii_composer 之前）加   - lua_processor@ascii_toggle

local K_ACCEPTED, K_NOOP = 1, 2
local XK_SPACE = 0x20

local P = {}

function P.func(key, env)
  local ok, result = pcall(function()
    if key:release() or key.keycode ~= XK_SPACE then return K_NOOP end
    if not (key:ctrl() and key:alt()) then return K_NOOP end

    local ctx = env.engine.context
    if ctx:is_composing() then
      env.engine:commit_text(ctx.input)
      ctx:clear()
    end
    ctx:set_option("ascii_mode", not ctx:get_option("ascii_mode"))
    return K_ACCEPTED
  end)
  if not ok then
    log.warning("ascii_toggle: " .. tostring(result))
    return K_NOOP
  end
  return result
end

return { P = P }
