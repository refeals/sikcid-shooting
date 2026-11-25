-- HUD strip at the top (Config.HUD_H).
--
-- One glass panel per player (P1 left, P2 right, same inner layout):
--   row 1: colored "Pn" tab, score, lives as mini ships;
--   row 2: combo count + multiplier with its timer bar, active power-ups;
--   row 3: permanent upgrades (square icons, level pips under them).
-- Center: wave number and enemies left (or the countdown between waves, or
-- the boss's name and HP bar on boss waves).

local Config = require("src.config")
local Combo  = require("src.systems.combo")
local Assets = require("src.assets")
local UI     = require("src.ui")
local Player = require("src.entities.player")
local Pickup = require("src.entities.pickup")
local Upgrades = require("src.systems.upgrades")

local Hud = {}

local PANEL_W, PANEL_H = 200, 44
local PAD = 4
local LIFE_GAP = 10           -- center-to-center spacing of the life ships
local COMBO_BAR_W = 92
local ICON = 11               -- power-up badge size
local ICON_GAP = 3
local UP_ICON = 9               -- permanent upgrade icon size (row 3)
local UP_GAP = 3
local PLAYER_TAGS = { "P1", "P2" }   -- built once: no string concat per frame
local BOSS_BAR_W = 150
local HC = Config.FX.hud
local scoreColor = { 1, 1, 1, 1 }    -- reused color buffers (no per-frame tables)
local lostColor = { 1, 1, 1, 1 }

-- Display state for each player (p.hud, made on first use): the score shown
-- running up to the real one, and the punch timers of the score and combo.
-- Runs on game time (Game:update); visual only, p.score is never touched.
function Hud.update(dt, players, count)
  for i = 1, count do
    local p = players[i]
    local h = p.hud
    if not h then
      h = { shown = p.score, last = p.score, kick = 0, kickBig = false,
            combo = p.combo or 0, comboKick = 0, comboBig = false, pulseWas = 0 }
      p.hud = h
    end
    -- Score: a gain starts a punch (bigger for big gains); the shown value
    -- runs after the real one, ~scoreCatchUp s, never slower than 400/s.
    if p.score > h.last then
      local gain = p.score - h.last
      h.kick = HC.scoreKick
      h.kickBig = gain >= HC.bigGain
      h.last = p.score
    elseif p.score < h.last then
      h.last, h.shown = p.score, p.score
    end
    local diff = p.score - h.shown
    if diff > 0 then
      local step = math.max(diff * (1 - math.exp(-dt * 3 / HC.scoreCatchUp)), 400 * dt)
      h.shown = math.min(p.score, h.shown + step)
    end
    if h.kick > 0 then h.kick = math.max(0, h.kick - dt) end
    -- Combo: a small punch per step, a big one when the multiplier pulse starts.
    local combo = p.combo or 0
    if combo > h.combo then h.comboKick, h.comboBig = HC.comboKick, false end
    h.combo = combo
    local pulse = p.comboPulse or 0
    if pulse > h.pulseWas then h.comboKick, h.comboBig = HC.comboKick * 1.5, true end
    h.pulseWas = pulse
    if h.comboKick > 0 then h.comboKick = math.max(0, h.comboKick - dt) end
  end
end

local function drawPowerups(p, x, y)
  local list = p.powerups
  if not list then return end
  for i = 1, #list do
    local pu = list[i]
    local cx = x + (i - 1) * (ICON + ICON_GAP) + ICON * 0.5
    Pickup.drawIcon(pu.def, cx, y + ICON * 0.5, ICON)
    -- Time left as a thin bar under the badge.
    local frac = pu.timeLeft / (pu.duration or pu.def.duration)
    love.graphics.setColor(Config.COLORS.hudLine)
    love.graphics.rectangle("fill", cx - ICON * 0.5, y + ICON + 1, ICON, 2)
    love.graphics.setColor(pu.def.color)
    love.graphics.rectangle("fill", cx - ICON * 0.5, y + ICON + 1, ICON * frac, 2)
  end
end

-- Row 3: permanent upgrades in the order they were taken, centered on `cy`;
-- one 1px pip under the icon per level above the first.
local function drawUpgrades(p, x, cy)
  local order = p.upgradeOrder
  if not order then return end
  local g = love.graphics
  for i = 1, #order do
    local id = order[i]
    local def = Upgrades.byId(id)
    local lvl = p.upgrades[id] or 1
    local ix = x + (i - 1) * (UP_ICON + UP_GAP) + UP_ICON * 0.5
    Upgrades.drawIcon(def, 1, ix, cy, UP_ICON)
    g.setColor(1, 1, 1, 0.9)
    for k = 2, lvl do
      g.rectangle("fill", math.floor(ix - (lvl - 1) * 1.5 + (k - 2) * 3), cy + UP_ICON * 0.5 + 1, 1, 1)
    end
  end
  g.setColor(1, 1, 1, 1)
end

local function drawPlayerPanel(p, x, y)
  local C = Config.COLORS
  UI.panel(x, y, PANEL_W, PANEL_H)

  -- Row 1: tab, score, lives. The score's baseline sits on the tab's bottom
  -- edge and the lives are centered on the tab.
  local tab = Config.ART.ui.hudTab
  UI.tab(p.color, PLAYER_TAGS[p.index], x + PAD, y + PAD, tab.w, tab.h)
  local font = Assets.font("digits")
  local h = p.hud
  local score = string.format("%07d", h and math.floor(h.shown) or p.score)
  local sx = x + PAD + tab.w + 6
  local sy = y + PAD + tab.h - font:getAscent()
  local sw = UI.digitsWidth("digits", score)
  -- Punch on each gain: grows around its center and goes toward white.
  local kick = h and h.kick / HC.scoreKick or 0
  local peak = (h and h.kickBig) and HC.bigKickScale or HC.kickScale
  local sc = 1 + (peak - 1) * kick
  local base = p.out and C.textDim or C.text
  local k = kick * 0.8
  scoreColor[1] = base[1] + (1 - base[1]) * k
  scoreColor[2] = base[2] + (1 - base[2]) * k
  scoreColor[3] = base[3] + (1 - base[3]) * k
  local fh = font:getHeight()
  love.graphics.push()
  love.graphics.translate(sx + sw * 0.5, sy + fh * 0.5)
  love.graphics.scale(sc, sc)
  UI.digits("digits", score, -sw * 0.5, -fh * 0.5, scoreColor)
  love.graphics.pop()

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
  local body = Assets.font("body")
  if p.comboLost and p.comboLost > 0 and p.combo == 0 then
    -- Lost: shakes sideways (calming down) and slides down as it fades.
    local t = p.comboLost / Config.COMBO.lostMsgTime          -- 1 -> 0
    local jx = math.sin(p.comboLost * 70) * HC.lostShake * t
    local w = C.doorWarn
    lostColor[1], lostColor[2], lostColor[3], lostColor[4] = w[1], w[2], w[3], math.min(1, t * 2)
    UI.text("body", "COMBO PERDIDO", x + PAD + 2 + jx, ry + HC.lostDrop * (1 - t), lostColor)
  elseif p.combo and p.combo > 0 then
    local mult = Combo.mult(p)
    local pulse = (p.comboPulse or 0) > 0
    local color = pulse and C.flash or (mult > 1 and C.textWarn or C.textDim)
    local text = string.format("COMBO %d  x%d", p.combo, mult)
    -- Punch on each step, bigger on a multiplier up.
    local ck = h and h.comboKick / HC.comboKick or 0
    local cpeak = (h and h.comboBig) and HC.bigKickScale or HC.kickScale
    local csc = 1 + (cpeak - 1) * math.min(1, ck)
    -- Grows from its left edge, so it never leaves the panel.
    local th = body:getHeight()
    love.graphics.push()
    love.graphics.translate(x + PAD + 2, ry + th * 0.5)
    love.graphics.scale(csc, csc)
    UI.text("body", text, 0, -th * 0.5, color)
    love.graphics.pop()
    local barColor = mult > 1 and C.textWarn or p.color
    UI.bar(barColor, x + PAD, ry + 10, COMBO_BAR_W, Combo.fraction(p), 4)
    if pulse then
      -- The bar flares while the new multiplier is highlighted.
      local a = p.comboPulse / Config.COMBO.pulseTime
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 1, 1, 0.5 * a)
      love.graphics.rectangle("fill", x + PAD, ry + 10, COMBO_BAR_W * Combo.fraction(p), 4)
      love.graphics.setBlendMode("alpha")
    end
  end
  drawPowerups(p, x + PAD + COMBO_BAR_W + 10, ry - 1)
  drawUpgrades(p, x + PAD + 1, y + 37)
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
  -- Label in the text font, number in the digits font (the Square fonts draw
  -- "0" as a box).
  if info then
    UI.textNumber("title", "digits", info.titleLabel, info.titleNum, nil, cx, 3, C.text, cw, "center")
    local boss = info.boss
    if boss then
      -- Boss wave: its name and HP bar in place of the enemy count. The bar
      -- turns warning red while it rages.
      local name = boss.variant.name
      local nw = Assets.font("body"):getWidth(name)
      local bx = cx + (cw - (nw + 6 + BOSS_BAR_W)) * 0.5
      UI.text("body", name, bx, 22, C.text)
      UI.bar(boss:isRaging() and C.doorWarn or boss.variant.color,
        bx + nw + 6, 24, BOSS_BAR_W, boss:fraction(), 6)
    else
      UI.textNumber("body", "digitsSmall", info.subLabel, info.subNum, nil, cx, 22, C.textDim, cw, "center")
    end
  else
    UI.text("title", "ARENA", cx, 3, C.text, cw, "center")
  end

  UI.exitBar(W * 0.5, Config.HUD_H - 7, 80)
  love.graphics.setColor(1, 1, 1, 1)
end

return Hud
