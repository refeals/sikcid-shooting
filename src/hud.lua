-- Faixa de HUD no topo da tela.
-- ETAPA 3: vidas e score. Combo, multiplicador, power-ups e info de wave
-- entram nas etapas 6/7.

local Config = require("src.config")
local Input  = require("src.input")

local Hud = {}

local LIFE_SIZE = 6
local LIFE_GAP = 3

local function drawLives(x, y, count, color)
  for i = 1, count do
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x + (i - 1) * (LIFE_SIZE + LIFE_GAP), y, LIFE_SIZE, LIFE_SIZE)
  end
end

-- `side` = "left" (P1) ou "right" (P2).
local function drawPlayerPanel(p, side)
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local x = side == "left" and 8 or W - 8
  local align = side == "left" and "left" or "right"
  local color = p.color

  love.graphics.setColor(color)
  love.graphics.printf(string.format("P%d", p.index),
    side == "left" and x or x - 120, 4, 120, align)

  love.graphics.setColor(p.out and C.textDim or C.text)
  love.graphics.printf(string.format("%07d", p.score),
    side == "left" and x + 24 or x - 140, 4, 120, align)

  if p.out then
    love.graphics.setColor(C.textDim)
    love.graphics.printf("FORA", side == "left" and x or x - 120, 20, 120, align)
  else
    local lw = p.lives * (LIFE_SIZE + LIFE_GAP)
    drawLives(side == "left" and x or x - lw, 22, p.lives, color)
  end
end

function Hud.draw(players, playerCount, info)
  local W = Config.VIRTUAL_W
  local C = Config.COLORS

  love.graphics.setColor(C.hudBg)
  love.graphics.rectangle("fill", 0, 0, W, Config.HUD_H)
  love.graphics.setColor(C.hudLine)
  love.graphics.line(0, Config.HUD_H + 0.5, W, Config.HUD_H + 0.5)

  if players[1] then drawPlayerPanel(players[1], "left") end
  if playerCount >= 2 and players[2] then drawPlayerPanel(players[2], "right") end

  -- Centro: informação de wave (preenchida a partir da etapa 5).
  love.graphics.setColor(C.text)
  love.graphics.printf(info and info.title or "ARENA", W * 0.5 - 100, 4, 200, "center")
  if info and info.subtitle then
    love.graphics.setColor(C.textDim)
    love.graphics.printf(info.subtitle, W * 0.5 - 100, 20, 200, "center")
  end

  -- Aviso discreto do combo de saída.
  local p = Input.exitProgress()
  if p > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W * 0.5 - 40, Config.HUD_H - 6, 80 * p, 3)
    love.graphics.setColor(C.textDim)
    love.graphics.printf("SAINDO...", W * 0.5 - 100, Config.HUD_H - 18, 200, "center")
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Hud
