-- Input of the menu screens (main menu, OPÇÕES, CRÉDITOS): any connected
-- device navigates, bound to a player or not.
--
--   local cmd, device = Nav.poll()   -- once per update
--     cmd: "up" | "down" | "left" | "right" | "confirm" | "back" | nil
--   Nav.tapped(action)               -- a finger just landed on that button
--
-- Pads and the keyboard go through the logical actions: START or A / Space
-- confirm, BACK or B / Backspace go back (ESC is the keyboard's BACK). The
-- touch screen only uses the buttons each screen registers while drawing
-- (Touch.button): unlike the lobby, a tap anywhere else is not START, so a
-- stray touch never picks an item. The VOLTAR button is the "back" action.

local Config = require("src.config")
local Input  = require("src.input")
local Touch  = require("src.touch")
local UI     = require("src.ui")
local S      = require("src.i18n").S

local Nav = {}

-- action -> held on the last check (edge detection for Nav.tapped).
local touchPrev = {}

function Nav.poll()
  for i = 1, Input.count do
    local d = Input.devices[i]
    if d.connected and d.kind ~= "touch" then
      if d:pressed("up") then return "up", d end
      if d:pressed("down") then return "down", d end
      if d:pressed("left") then return "left", d end
      if d:pressed("right") then return "right", d end
      if d:pressed("start") or d:pressed("accept") then return "confirm", d end
      -- BACK with START held is the start of the quit combo, not a step back.
      if (d:pressed("back") and not d:isDown("start")) or d:pressed("cancel") then
        return "back", d
      end
    end
  end
  local t = Input.touch
  if t and t.connected and t:pressed("back") then return "back", t end
  return nil
end

-- True on the frame a finger lands on the button registered as `action`
-- (call it every frame for each button the screen shows).
function Nav.tapped(action)
  local down = Touch.actionDown(action)
  local was = touchPrev[action]
  touchPrev[action] = down
  return down and not was
end

-- The VOLTAR button of the touch screen (the "back" action), centered at
-- `y` (default Config.MENU.touchBack.y). Shown only while the last input
-- was a touch: pads and keyboards have BACK.
function Nav.drawTouchBack(y)
  if not Input.usingTouch() then return end
  local B = Config.MENU.touchBack
  local x = math.floor((Config.VIRTUAL_W - B.w) * 0.5)
  y = y or B.y
  UI.tab(Config.ART.ui.neutral, S.back_button, x, y, B.w, B.h, "titleSmall")
  Touch.button("back", x, y, B.w, B.h)
end

return Nav
