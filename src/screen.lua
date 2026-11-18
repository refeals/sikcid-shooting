-- Virtual 640x360 screen, rendered at an integer multiple of that size.
--
-- All game code draws in 640x360 logical coordinates. The canvas itself is
-- (640*k) x (360*k), with k the largest integer that fits the window, and
-- beginDraw() applies love.graphics.scale(k). So 720p renders at 1280x720,
-- 1080p at 1920x1080 (no letterbox), and smooth sprites keep their detail
-- while gameplay math is untouched. The final blit is 1:1 unless
-- Config.ART.maxRenderScale caps k below the window's multiple.

local Config = require("src.config")

local Screen = {
  canvas = nil,
  scale = 1,          -- window px per logical px (integer)
  renderScale = 1,    -- canvas px per logical px (k)
  offsetX = 0,
  offsetY = 0,
  shakeX = 0,
  shakeY = 0,
}

local VW, VH = Config.VIRTUAL_W, Config.VIRTUAL_H

function Screen.load()
  Screen.resize(love.graphics.getDimensions())
end

-- Recomputes the integer scale, the letterbox and, when k changes, the canvas.
function Screen.resize(w, h)
  local s = math.floor(math.min(w / VW, h / VH))
  if s < 1 then s = 1 end
  Screen.scale = s
  Screen.offsetX = math.floor((w - VW * s) * 0.5)
  Screen.offsetY = math.floor((h - VH * s) * 0.5)

  local k = s
  local cap = Config.ART.maxRenderScale
  if cap and k > cap then k = cap end
  if k ~= Screen.renderScale or not Screen.canvas then
    if Screen.canvas then Screen.canvas:release() end
    Screen.renderScale = k
    Screen.canvas = love.graphics.newCanvas(VW * k, VH * k)
    -- Only matters when k is capped and the blit has to upscale.
    Screen.canvas:setFilter("linear", "linear")
  end
end

-- Screen-shake offset applied to the whole frame (logical px).
function Screen.setShake(x, y)
  Screen.shakeX, Screen.shakeY = x, y
end

function Screen.beginDraw()
  local k = Screen.renderScale
  love.graphics.setCanvas(Screen.canvas)
  love.graphics.clear(Config.COLORS.bg)
  love.graphics.push()
  -- Shake snaps to whole logical px, as before the high-res canvas.
  love.graphics.translate(math.floor(Screen.shakeX) * k, math.floor(Screen.shakeY) * k)
  love.graphics.scale(k, k)
end

function Screen.endDraw()
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.clear(Config.COLORS.letterbox)
  love.graphics.setColor(1, 1, 1, 1)
  local blit = Screen.scale / Screen.renderScale
  love.graphics.draw(Screen.canvas, Screen.offsetX, Screen.offsetY, 0, blit, blit)
end

-- Converts window coordinates to logical coordinates (mouse/debug).
function Screen.toVirtual(x, y)
  return (x - Screen.offsetX) / Screen.scale, (y - Screen.offsetY) / Screen.scale
end

return Screen
