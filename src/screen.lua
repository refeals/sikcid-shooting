-- Canvas virtual 640x360 com escala inteira e letterbox.
-- Todo o desenho do jogo acontece em coordenadas virtuais.

local Config = require("src.config")

local Screen = {
  canvas = nil,
  scale = 1,
  offsetX = 0,
  offsetY = 0,
  shakeX = 0,
  shakeY = 0,
}

local VW, VH = Config.VIRTUAL_W, Config.VIRTUAL_H

function Screen.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  Screen.canvas = love.graphics.newCanvas(VW, VH)
  Screen.canvas:setFilter("nearest", "nearest")
  Screen.resize(love.graphics.getDimensions())
end

-- Recalcula escala inteira e as barras pretas.
function Screen.resize(w, h)
  local s = math.min(w / VW, h / VH)
  s = math.floor(s)
  if s < 1 then s = 1 end
  Screen.scale = s
  Screen.offsetX = math.floor((w - VW * s) * 0.5)
  Screen.offsetY = math.floor((h - VH * s) * 0.5)
end

-- Offset de screen shake aplicado no draw final (em pixels virtuais).
function Screen.setShake(x, y)
  Screen.shakeX, Screen.shakeY = x, y
end

function Screen.beginDraw()
  love.graphics.setCanvas(Screen.canvas)
  love.graphics.clear(Config.COLORS.bg)
  love.graphics.push()
  love.graphics.translate(math.floor(Screen.shakeX), math.floor(Screen.shakeY))
end

function Screen.endDraw()
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.clear(Config.COLORS.letterbox)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Screen.canvas, Screen.offsetX, Screen.offsetY, 0, Screen.scale, Screen.scale)
end

-- Converte coordenada de janela para coordenada virtual (mouse/debug).
function Screen.toVirtual(x, y)
  return (x - Screen.offsetX) / Screen.scale, (y - Screen.offsetY) / Screen.scale
end

return Screen
