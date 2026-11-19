-- Touch screen state: the fingers on the glass and the on-screen buttons.
--
-- Everything here is in LOGICAL coordinates (main.lua converts with
-- Screen.toVirtual). The touch DEVICE (src/input.lua) reads this module; the
-- screens tell it what a touch means by what they DRAW each frame:
--
--   Touch.beginFrame()          -- love.draw, before the states draw
--   Touch.button(action, ...)   -- a tappable rect (pause, color arrows...)
--   Touch.useSticks()           -- the arena: fingers become analog sticks
--
-- so a touch always answers to what was on screen when it landed. A finger
-- that lands on a button holds that action; in the arena it becomes the move
-- stick (left half) or the aim stick (right half); anywhere else it is a
-- "tap", which counts as START. Fixed slots: nothing is allocated per touch.

local Config = require("src.config")

local Touch = {}

local T = Config.TOUCH
local MAX_FINGERS = 5
local MAX_BUTTONS = 8

-- fingers[i] = { id, role = "move"|"aim"|"tap"|"button"|"none", action,
--                x, y, baseX, baseY }; id == nil = free slot.
local fingers = {}
for i = 1, MAX_FINGERS do
  fingers[i] = { id = nil, role = "none", action = nil, x = 0, y = 0, baseX = 0, baseY = 0 }
end

-- Buttons registered by the screen drawn last frame.
local buttons = {}
for i = 1, MAX_BUTTONS do buttons[i] = { action = nil, x = 0, y = 0, w = 0, h = 0 } end
local buttonCount = 0
local sticks = false

-- What the screen drawn last frame offered; touches landing now use it.
local liveButtons, liveCount, liveSticks = {}, 0, false
for i = 1, MAX_BUTTONS do liveButtons[i] = { action = nil, x = 0, y = 0, w = 0, h = 0 } end

function Touch.beginFrame()
  -- Freeze what the previous frame showed, then start collecting anew.
  for i = 1, buttonCount do
    local s, d = buttons[i], liveButtons[i]
    d.action, d.x, d.y, d.w, d.h = s.action, s.x, s.y, s.w, s.h
  end
  liveCount, liveSticks = buttonCount, sticks
  buttonCount, sticks = 0, false
end

function Touch.button(action, x, y, w, h)
  if buttonCount >= MAX_BUTTONS then return end
  buttonCount = buttonCount + 1
  local b = buttons[buttonCount]
  b.action, b.x, b.y, b.w, b.h = action, x, y, w, h
end

function Touch.useSticks()
  sticks = true
end

-- For the smoke bot (--smoketouch): where to tap for `action`, and whether
-- the screen on display takes sticks.
function Touch.buttonCenter(action)
  for i = liveCount, 1, -1 do
    local b = liveButtons[i]
    if b.action == action then return b.x + b.w * 0.5, b.y + b.h * 0.5 end
  end
  return nil
end

function Touch.sticksLive()
  return liveSticks
end

local function findFinger(id)
  for i = 1, MAX_FINGERS do
    if fingers[i].id == id then return fingers[i] end
  end
  return nil
end

local function roleTaken(role)
  for i = 1, MAX_FINGERS do
    local f = fingers[i]
    if f.id ~= nil and f.role == role then return true end
  end
  return false
end

local function buttonAt(x, y)
  local pad = T.buttonPad
  for i = liveCount, 1, -1 do   -- last drawn = on top
    local b = liveButtons[i]
    if x >= b.x - pad and x <= b.x + b.w + pad and y >= b.y - pad and y <= b.y + b.h + pad then
      return b
    end
  end
  return nil
end

function Touch.pressed(id, x, y)
  if findFinger(id) then return end
  local f = findFinger(nil)
  if not f then return end   -- more fingers than slots: ignored
  f.id, f.x, f.y, f.baseX, f.baseY, f.action = id, x, y, x, y, nil
  local b = buttonAt(x, y)
  if b then
    f.role, f.action = "button", b.action
  elseif liveSticks then
    f.role = "none"
    if y >= Config.HUD_H then
      local want = x < Config.VIRTUAL_W * 0.5 and "move" or "aim"
      if not roleTaken(want) then f.role = want end
    end
  else
    f.role = "tap"
  end
end

function Touch.moved(id, x, y)
  local f = findFinger(id)
  if not f then return end
  f.x, f.y = x, y
  -- The stick base follows a finger dragged past its radius: turning back
  -- is always one radius away.
  if f.role == "move" or f.role == "aim" then
    local dx, dy = x - f.baseX, y - f.baseY
    local d2 = dx * dx + dy * dy
    local r = T.stickRadius
    if d2 > r * r then
      local d = math.sqrt(d2)
      f.baseX, f.baseY = x - dx / d * r, y - dy / d * r
    end
  end
end

function Touch.released(id)
  local f = findFinger(id)
  if f then f.id, f.role, f.action = nil, "none", nil end
end

-- Lets go of every finger (the window lost focus: no release will come).
function Touch.releaseAll()
  for i = 1, MAX_FINGERS do
    local f = fingers[i]
    f.id, f.role, f.action = nil, "none", nil
  end
end

-- Is `action` held? A plain tap holds START.
function Touch.actionDown(action)
  for i = 1, MAX_FINGERS do
    local f = fingers[i]
    if f.id ~= nil then
      if f.role == "button" and f.action == action then return true end
      if f.role == "tap" and action == "start" then return true end
    end
  end
  return false
end

-- Stick vector for "move" or "aim": (finger - base) / radius, length <= 1.
function Touch.stick(role)
  for i = 1, MAX_FINGERS do
    local f = fingers[i]
    if f.id ~= nil and f.role == role then
      local r = T.stickRadius
      return (f.x - f.baseX) / r, (f.y - f.baseY) / r
    end
  end
  return 0, 0
end

-- ---------------------------------------------------------------------------
-- Drawing (arena only): the sticks under the fingers, and faint ghosts in the
-- bottom corners showing where to touch while a side is free.
-- ---------------------------------------------------------------------------
local function drawStick(bx, by, kx, ky, color, alpha)
  local g = love.graphics
  g.setColor(color[1], color[2], color[3], 0.12 * alpha)
  g.circle("fill", bx, by, T.stickRadius)
  g.setColor(color[1], color[2], color[3], 0.45 * alpha)
  g.setLineWidth(1.5)
  g.circle("line", bx, by, T.stickRadius)
  g.setLineWidth(1)
  g.setColor(color[1], color[2], color[3], 0.55 * alpha)
  g.circle("fill", kx, ky, T.knobRadius)
end

local ghostText = { 1, 1, 1, 1 }

function Touch.drawSticks(color)
  local UI = require("src.ui")
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local hasMove, hasAim = false, false
  for i = 1, MAX_FINGERS do
    local f = fingers[i]
    if f.id ~= nil and (f.role == "move" or f.role == "aim") then
      if f.role == "move" then hasMove = true else hasAim = true end
      drawStick(f.baseX, f.baseY, f.x, f.y, color, 1)
    end
  end
  local inset, r, a = T.ghostInset, T.ghostRadius, T.ghostAlpha
  local C = Config.COLORS.text
  ghostText[1], ghostText[2], ghostText[3], ghostText[4] = C[1], C[2], C[3], a * 2.5
  local ghost = ghostText
  if not hasMove then
    love.graphics.setColor(C[1], C[2], C[3], a)
    love.graphics.circle("line", inset, H - inset, r)
    UI.text("body", "MOVER", inset - 30, H - inset - 3, ghost, 60, "center")
  end
  if not hasAim then
    love.graphics.setColor(C[1], C[2], C[3], a)
    love.graphics.circle("line", W - inset, H - inset, r)
    UI.text("body", "MIRAR", W - inset - 30, H - inset - 3, ghost, 60, "center")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Touch
