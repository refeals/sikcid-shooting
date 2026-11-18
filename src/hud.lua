-- HUD strip at the top (40px).
--
-- One glass panel per player (P1 left, P2 right, same inner layout):
--   row 1: colored "Pn" tab, score, lives as mini ships;
--   row 2: combo count + multiplier with its timer bar, active power-ups.
-- Center: wave number and enemies left (or the countdown between waves).

local Config = require("src.config")
local Combo  = require("src.systems.combo")
local Assets = require("src.assets")
local UI     = require("src.ui")
local Player = require("src.entities.player")
local Pickup = require("src.entities.pickup")

local Hud = {}

local PANEL_W, PANEL_H = 200, 36
local PAD = 4
local LIFE_GAP = 10           -- center-to-center spacing of the life ships
local COMBO_BAR_W = 92
local ICON = 11               -- power-up badge size
local ICON_GAP = 3
local PLAYER_TAGS = { "P1", "P2" }   -- built once: no string concat per frame

local function drawPowerups(p, x, y)
  local list = p.powerups
  if not list then return end
  for i = 1, #list do
    local pu = list[i]
    local cx = x + (i - 1) * (ICON + ICON_GAP) + ICON * 0.5
    Pickup.drawIcon(pu.def, cx, y + ICON * 0.5, ICON)
    -- Time left as a thin bar under the badge.
    local frac = pu.timeLeft / pu.def.duration
    love.graphics.setColor(Config.COLORS.hudLine)
    love.graphics.rectangle("fill", cx - ICON * 0.5, y + ICON + 1, ICON, 2)
    love.graphics.setColor(pu.def.color)
    love.graphics.rectangle("fill", cx - ICON * 0.5, y + ICON + 1, ICON * frac, 2)
  end
end

local function drawPlayerPanel(p, x, y)
  local C = Config.COLORS
  UI.panel(x, y, PANEL_W, PANEL_H)

  -- Row 1: tab, score, lives. The score's baseline sits on the tab's bottom
  -- edge and the lives are centered on the tab.
  local tab = Config.ART.ui.hudTab
  UI.tab(p.color, PLAYER_TAGS[p.index], x + PAD, y + PAD, tab.w, tab.h)
  local font = Assets.font("digits")
  local score = string.format("%07d", p.score)
  local sx = x + PAD + tab.w + 6
  local sw = UI.digits("digits", score, sx, y + PAD + tab.h - font:getAscent(), p.out and C.textDim or C.text)

  local lx = sx + sw + 10
  local midY = y + PAD + tab.h * 0.5
  if p.out then
    UI.text("body", "FORA", lx, midY - 3, C.textDim)
  else
    for i = 1, p.lives do
      Player.drawShip(p.color, lx + (i - 1) * LIFE_GAP, midY, -math.pi / 2, Config.ART.size.hudLife)
    end
  end

  -- Row 2: combo text + bar on the left, power-ups on the right.
  local ry = y + 18
  if p.comboLost and p.comboLost > 0 and p.combo == 0 then
    if math.floor(p.comboLost * 10) % 2 == 0 then
      UI.text("body", "COMBO PERDIDO", x + PAD + 2, ry, C.doorWarn)
    end
  elseif p.combo and p.combo > 0 then
    local mult = Combo.mult(p)
    local color = (p.comboPulse or 0) > 0 and C.flash or (mult > 1 and C.textWarn or C.textDim)
    UI.text("body", string.format("COMBO %d  x%d", p.combo, mult), x + PAD + 2, ry, color)
    UI.bar(mult > 1 and C.textWarn or p.color, x + PAD, ry + 10, COMBO_BAR_W, Combo.fraction(p), 4)
  end
  drawPowerups(p, x + PAD + COMBO_BAR_W + 10, ry - 1)
end

function Hud.draw(players, playerCount, info)
  local W = Config.VIRTUAL_W
  local C = Config.COLORS

  love.graphics.setColor(C.hudBg)
  love.graphics.rectangle("fill", 0, 0, W, Config.HUD_H)
  love.graphics.setColor(C.hudLine)
  love.graphics.line(0, Config.HUD_H + 0.5, W, Config.HUD_H + 0.5)

  if players[1] then drawPlayerPanel(players[1], 2, 2) end
  if playerCount >= 2 and players[2] then drawPlayerPanel(players[2], W - PANEL_W - 2, 2) end

  -- Center: wave and enemies left.
  local cx = PANEL_W + 6
  local cw = W - 2 * cx
  UI.text("title", info and info.title or "ARENA", cx, 3, C.text, cw, "center")
  if info and info.subtitle then
    UI.text("body", info.subtitle, cx, 22, C.textDim, cw, "center")
  end

  UI.exitBar(W * 0.5, Config.HUD_H - 7, 80)
  love.graphics.setColor(1, 1, 1, 1)
end

return Hud
