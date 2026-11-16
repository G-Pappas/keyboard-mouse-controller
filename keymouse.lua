-- Keyboard mouse mode: drive the pointer with the arrow keys.
--
--   SUPER + N      enter / leave the mode (Escape also leaves)
--   Arrows         move: tap = small step, hold = glide and speed up
--   Shift + Arrows move slowly, for the last few pixels
--   Ctrl + Arrows  move fast
--   S (hold) + Arrows  scroll; the longer you hold, the faster. PgUp / PgDn also scroll
--   Enter          click (twice quickly = double click, selects a word)
--   Space (hold)   select: holds the left button while Space is down
--   C              copy the selection
--   V              paste
--   R              right click
--
-- Hyprland moves the pointer itself; clicks go through a virtual pointer kept
-- by the keymouse-daemon next to this file, because Hyprland has no click
-- dispatcher.

local SUBMAP = "keymouse"
local ENTER_KEY = "SUPER + N"

local TICK_MS = 16 -- glide refresh
local TAP_STEP = 8 -- pixels per tap
local TAP_STEP_SLOW = 1 -- pixels per tap with Shift
local HOLD_TICKS = 11 -- ticks a key is held before the glide starts
local SPEED_START = 3 -- glide speed in pixels per tick
local SPEED_GAIN = 0.45 -- added per tick while held
local SPEED_MAX = 26
local SPEED_SLOW = 1.5 -- glide speed with Shift
local SCROLL_EVERY = 4 -- ticks between scroll steps while an arrow is held
local SCROLL_RAMP = 20 -- ticks of holding for each extra notch per step
local SCROLL_MAX = 6 -- most notches per step
local FAST = 4 -- Ctrl multiplies the tap step and the glide speed by this

-- The click helper sits next to this file, wherever the plugin is installed.
local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$")
  or (os.getenv("HOME") .. "/.config/omarchy/plugins/gpappas.keymouse")
local daemon = here .. "/keymouse-daemon"
local fifo = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/keymouse.fifo"

local HELP = "MOUSE MODE   Arrows move (Shift slow, Ctrl fast)   hold S + Arrows scroll   Enter click   hold Space select   C copy   V paste   Esc exit"
local HELP_SELECTING = "SELECTING   Arrows extend   release Space to stop"

local state = {
  active = false,
  selecting = false,
  ticks = 0,
  note = nil,
  timer = nil,
  hide_on_key_press = nil,
}

-- ("test", not "[": Hyprland reads a leading "[" as window rules.)
-- The fifo check keeps a write from creating a plain file when the daemon has
-- never run; the timeout keeps one from hanging when the daemon has died.
local function send(...)
  local commands = table.concat({ ... }, " ")
  hl.exec_cmd(("test -p '%s' && timeout 1 sh -c 'printf \"%%s\\n\" %s > \"%s\"'"):format(fifo, commands, fifo))
end

local function show(text, color)
  if state.note then
    pcall(function() state.note:dismiss() end)
  end
  state.note = hl.notification.create({ text = text, timeout = 3600000, color = color })
end

local function hide_note()
  if state.note then
    pcall(function() state.note:dismiss() end)
    state.note = nil
  end
end

local function move(dx, dy)
  local pos = hl.get_cursor_pos()
  if pos then
    hl.dispatch(hl.dsp.cursor.move({ x = pos.x + dx, y = pos.y + dy }))
  end
end

local function shift_down()
  return hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R")
end

-- S is the scroll key rather than a modifier: apps see held modifiers, and
-- Alt, or Ctrl (which zooms in browsers), would change what the wheel does.
local function scroll_held()
  return hl.is_key_down("s")
end

local function ctrl_down()
  return hl.is_key_down("Control_L") or hl.is_key_down("Control_R")
end

local function direction()
  local dx = (hl.is_key_down("Right") and 1 or 0) - (hl.is_key_down("Left") and 1 or 0)
  local dy = (hl.is_key_down("Down") and 1 or 0) - (hl.is_key_down("Up") and 1 or 0)
  return dx, dy
end

local function set_selecting(on)
  if state.selecting == on then
    return
  end
  state.selecting = on
  send(on and "down" or "up")
  if state.active then
    if on then
      show(HELP_SELECTING, "rgba(ffb000ff)")
    else
      show(HELP, "rgba(33ccffff)")
    end
  end
end

local function scroll(dx, dy, notches)
  local name
  if dy ~= 0 then
    name = dy < 0 and "scroll-up" or "scroll-down"
  else
    name = dx < 0 and "scroll-left" or "scroll-right"
  end
  send(notches and notches > 1 and (name .. ":" .. notches) or name)
end

local function tick()
  -- Selecting lasts only while Space is held. Polled here because Hyprland
  -- skips release binds when another key (an arrow) was released meanwhile.
  if state.selecting and not hl.is_key_down("space") then
    set_selecting(false)
  end

  local dx, dy = direction()
  if dx == 0 and dy == 0 then
    state.ticks = 0
    return
  end

  state.ticks = state.ticks + 1
  if state.ticks <= HOLD_TICKS then
    return
  end

  if scroll_held() then
    local held = state.ticks - HOLD_TICKS
    if held % SCROLL_EVERY == 0 then
      scroll(dx, dy, math.min(1 + math.floor(held / SCROLL_RAMP), SCROLL_MAX))
    end
    return
  end

  local speed = SPEED_SLOW
  if not shift_down() then
    speed = math.min(SPEED_START + (state.ticks - HOLD_TICKS) * SPEED_GAIN, SPEED_MAX)
    if ctrl_down() then
      speed = speed * FAST
    end
  end
  move(dx * speed, dy * speed)
end

local function tap(dx, dy)
  return function()
    if scroll_held() then
      scroll(dx, dy)
      return
    end
    local step = TAP_STEP
    if shift_down() then
      step = TAP_STEP_SLOW
    elseif ctrl_down() then
      step = TAP_STEP * FAST
    end
    move(dx * step, dy * step)
  end
end

local function enter()
  state.active = true
  state.selecting = false
  state.ticks = 0

  -- Starts the virtual mouse if it is not running; otherwise a wiggle brings
  -- back a pointer that hid itself while typing.
  hl.exec_cmd(daemon)
  send("wiggle")

  state.hide_on_key_press = hl.get_config("cursor.hide_on_key_press")
  hl.config({ cursor = { hide_on_key_press = false } })

  show(HELP, "rgba(33ccffff)")

  if state.timer then
    state.timer:set_enabled(true)
  else
    state.timer = hl.timer(tick, { timeout = TICK_MS, type = "repeat" })
  end
end

local function leave()
  state.active = false
  state.selecting = false
  -- The nudge is a real pointer event, so Hyprland focuses whatever window the
  -- pointer is over now (the arrow keys only warp it, which doesn't).
  send("up", "wiggle")
  hide_note()

  if state.timer then
    state.timer:set_enabled(false)
  end
  if state.hide_on_key_press ~= nil then
    hl.config({ cursor = { hide_on_key_press = state.hide_on_key_press } })
    state.hide_on_key_press = nil
  end
end

hl.on("keybinds.submap", function(name)
  if name == SUBMAP then
    enter()
  elseif state.active then
    leave()
  end
end)

-- Same shortcuts as Omarchy's universal copy and paste (SUPER + C / V):
-- terminals take Ctrl + Shift, everything else takes Ctrl.
local function active_window_is_terminal()
  local window = hl.get_active_window()
  for _, tag in ipairs((window and window.tags) or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function clipboard(key)
  return function()
    set_selecting(false)
    -- Give the app a moment to see the button release before the shortcut.
    hl.timer(function()
      local mods = active_window_is_terminal() and "CTRL SHIFT" or "CTRL"
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
      hl.timer(function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
      end, { timeout = 50, type = "oneshot" })
    end, { timeout = 80, type = "oneshot" })
  end
end

local function command(name)
  return function()
    send(name)
  end
end

o.bind(ENTER_KEY, "Mouse mode (arrow keys move the pointer)", hl.dsp.submap(SUBMAP))

hl.define_submap(SUBMAP, function()
  local any_mods = { ignore_mods = true }

  hl.bind("Left", tap(-1, 0), any_mods)
  hl.bind("Right", tap(1, 0), any_mods)
  hl.bind("Up", tap(0, -1), any_mods)
  hl.bind("Down", tap(0, 1), any_mods)

  hl.bind("Return", command("click"))
  hl.bind("KP_Enter", command("click"))
  hl.bind("R", command("rclick"))
  hl.bind("Space", function() set_selecting(true) end, any_mods)
  -- Only here so the letter isn't typed into the app; arrows check it is held.
  hl.bind("S", hl.dsp.no_op(), any_mods)

  hl.bind("C", clipboard("C"))
  hl.bind("V", clipboard("V"))

  hl.bind("Prior", command("scroll-up"), { repeating = true })
  hl.bind("Next", command("scroll-down"), { repeating = true })

  hl.bind("Escape", hl.dsp.submap("reset"))
  hl.bind(ENTER_KEY, hl.dsp.submap("reset"))
end)
