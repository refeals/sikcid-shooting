-- Faixa de HUD no topo (40px).
--
-- Esquerda = P1, direita = P2: vidas, score, combo + multiplicador + barra de
-- tempo, e ícones dos power-ups ativos com barra de duração.
-- Centro: número da wave e inimigos restantes na cota.

local Config = require("src.config")
local Input  = require("src.input")
local Combo  = require("src.systems.combo")

local Hud = {}

local LIFE_SIZE = 5
local LIFE_GAP = 3
local COMBO_BAR_W = 64
local ICON = 9

-- Desenha um retângulo "ancorado": em `align == "right"` cresce para a
-- esquerda a partir de x. Evita duplicar toda a matemática de layout.
local function rect(mode, align, x, y, w, h)
  love.graphics.rectangle(mode, align == "right" and (x - w) or x, y, w, h)
end

local function drawLives(align, x, y, count, color)
  love.graphics.setColor(color)
  for i = 1, count do
    local off = (i - 1) * (LIFE_SIZE + LIFE_GAP)
    rect("fill", align, align == "right" and (x - off) or (x + off), y, LIFE_SIZE, LIFE_SIZE)
  end
end

local function drawPowerups(p, align, x, y)
  local list = p.powerups
  if not list then return end
  for i = 1, #list do
    local pu = list[i]
    local off = (i - 1) * (ICON + 3)
    local ix = align == "right" and (x - off) or (x + off)

    love.graphics.setColor(pu.def.color or Config.COLORS.text)
    rect("fill", align, ix, y, ICON, ICON)

    -- Barra de tempo restante embaixo do ícone.
    local frac = pu.timeLeft / pu.def.duration
    love.graphics.setColor(Config.COLORS.hudLine)
    rect("fill", align, ix, y + ICON + 1, ICON, 2)
    love.graphics.setColor(Config.COLORS.text)
    rect("fill", align, ix, y + ICON + 1, ICON * frac, 2)
  end
end

-- `align` = "left" (P1) ou "right" (P2); `x` é a borda de ancoragem.
local function drawPlayerPanel(p, align, x)
  local C = Config.COLORS
  local textX = align == "right" and (x - 160) or x

  love.graphics.setColor(p.color)
  love.graphics.printf(string.format("P%d", p.index), textX, 2, 160, align)

  love.graphics.setColor(p.out and C.textDim or C.text)
  love.graphics.printf(string.format("%07d", p.score),
    align == "right" and (textX - 22) or (textX + 22), 2, 160, align)

  if p.out then
    love.graphics.setColor(C.textDim)
    love.graphics.printf("FORA", textX, 14, 160, align)
  else
    drawLives(align, x, 15, p.lives, p.color)
  end

  -- Combo: contagem, multiplicador e barra encolhendo (linha própria, abaixo
  -- do texto, para não parecer um sublinhado).
  if p.comboLost and p.comboLost > 0 and p.combo == 0 then
    -- Aviso piscando ao perder o combo.
    if math.floor(p.comboLost * 10) % 2 == 0 then
      love.graphics.setColor(C.doorWarn)
      love.graphics.printf("COMBO PERDIDO", textX, 23, 160, align)
    end
  elseif p.combo and p.combo > 0 then
    local mult = Combo.mult(p)
    love.graphics.setColor(mult > 1 and C.textWarn or C.textDim)
    love.graphics.printf(string.format("COMBO %d  x%d", p.combo, mult),
      textX, 23, 160, align)

    local frac = Combo.fraction(p)
    love.graphics.setColor(C.hudLine)
    rect("fill", align, x, 36, COMBO_BAR_W, 3)
    love.graphics.setColor(p.color)
    rect("fill", align, x, 36, COMBO_BAR_W * frac, 3)
  end

  drawPowerups(p, align, align == "right" and (x - COMBO_BAR_W - 10) or (x + COMBO_BAR_W + 10), 21)
end

function Hud.draw(players, playerCount, info)
  local W = Config.VIRTUAL_W
  local C = Config.COLORS

  love.graphics.setColor(C.hudBg)
  love.graphics.rectangle("fill", 0, 0, W, Config.HUD_H)
  love.graphics.setColor(C.hudLine)
  love.graphics.line(0, Config.HUD_H + 0.5, W, Config.HUD_H + 0.5)

  if players[1] then drawPlayerPanel(players[1], "left", 6) end
  if playerCount >= 2 and players[2] then drawPlayerPanel(players[2], "right", W - 6) end

  -- Centro: wave e inimigos restantes.
  love.graphics.setColor(C.text)
  love.graphics.printf(info and info.title or "ARENA", W * 0.5 - 90, 4, 180, "center")
  if info and info.subtitle then
    love.graphics.setColor(C.textDim)
    love.graphics.printf(info.subtitle, W * 0.5 - 90, 18, 180, "center")
  end

  -- Aviso discreto do combo de saída (select+start).
  local ex = Input.exitProgress()
  if ex > 0 then
    love.graphics.setColor(C.textDim)
    love.graphics.printf("SAINDO", W * 0.5 - 60, Config.HUD_H - 14, 120, "center")
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W * 0.5 - 30, Config.HUD_H - 4, 60 * ex, 2)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Hud
