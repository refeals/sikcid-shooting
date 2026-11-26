-- Upgrade pick: overlay over the frozen arena, every Config.UPGRADES.every
-- waves (pushed by Game:update in the breather, or F7 in debug).
--
-- Each player gets their own cards (Upgrades.offer) and picks one: left /
-- right moves, START confirms; on the touch screen a tap on a card picks it.
-- With two players the screen splits (P1 left, P2 right) and the match goes
-- on once both have confirmed. Players who ran out pick too (they are back
-- next wave). The Game below is frozen, so the breather countdown waits.

local Config   = require("src.config")
local Input    = require("src.input")
local Touch    = require("src.touch")
local State    = require("src.state")
local Audio    = require("src.audio")
local UI       = require("src.ui")
local Screen   = require("src.screen")
local Upgrades = require("src.systems.upgrades")
local S        = require("src.i18n").S

local U = Config.UPGRADES
local CARDS = 3

local Upgrade = {}

-- Per player: the cards (reused { def, level } slots), how many, the cursor
-- and whether they confirmed. Touch: one button action per card, built once.
local offers = { {}, {} }
local picks = {
  { n = 0, cursor = 2, confirmed = false },
  { n = 0, cursor = 2, confirmed = false },
}
local CARD_ACTIONS = {}
for i = 1, 2 do
  CARD_ACTIONS[i] = {}
  for k = 1, CARDS do CARD_ACTIONS[i][k] = string.format("card%d%d", i, k) end
end
local touchPrev = {}

function Upgrade:enter(world, boss)
  self.world = world
  self.boss = boss and true or false
  self.timer = 0
  for i = 1, world.playerCount do
    local s = picks[i]
    s.n = Upgrades.offer(world.players[i], self.boss, offers[i], CARDS)
    s.cursor = math.min(2, s.n)
    s.confirmed = false
  end
  for k in pairs(touchPrev) do touchPrev[k] = false end
  Screen.setShake(0, 0)      -- the frozen arena must not stay offset
  Audio.play("menu_confirm")
  if Config.SMOKE then require("src.smoke").note("upgradeOpen", true) end
end

function Upgrade:leave()
  if Config.SMOKE then require("src.smoke").note("upgradeOpen", false) end
end

-- Where a player's pick shows in the arena: the ship, or the respawn marker.
local function anchor(p)
  if p.alive then return p.x, p.y end
  return p.markerX, p.markerY
end

local function confirm(self, i)
  local p = self.world.players[i]
  local s = picks[i]
  local card = offers[i][s.cursor]
  Upgrades.take(p, card.def)
  s.confirmed = true
  Audio.play("pickup_life", 1, U.pickPitch)
  local color = Upgrades.color(card.def)
  local x, y = anchor(p)
  self.world:ring(x, y, 30, color, 0.45)
  self.world:floatText(x, y - 14, Upgrades.label(card.def, card.level), color)
  if Config.SMOKE then require("src.smoke").bump("upgrades") end
end

function Upgrade:update(dt)
  self.timer = self.timer + dt
  local world = self.world
  local ready = self.timer >= U.acceptDelay
  local all = true
  for i = 1, world.playerCount do
    local s = picks[i]
    if not s.confirmed then
      local d = world.players[i].device
      if ready and d and d.connected then
        if d.kind == "touch" then
          -- A tap on a card picks it (edge: the finger has to land on it).
          for k = 1, s.n do
            local a = CARD_ACTIONS[i][k]
            local down = Touch.actionDown(a)
            if down and not touchPrev[a] and not s.confirmed then
              s.cursor = k
              confirm(self, i)
            end
            touchPrev[a] = down
          end
        elseif d:pressed("left") and s.cursor > 1 then
          s.cursor = s.cursor - 1
          Audio.play("menu_move")
        elseif d:pressed("right") and s.cursor < s.n then
          s.cursor = s.cursor + 1
          Audio.play("menu_move")
        elseif d:pressed("start") then
          confirm(self, i)
        end
      end
      if not s.confirmed then all = false end
    end
  end
  if all then State.pop() end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local cardColor = { 1, 1, 1, 1 }

local function drawCard(card, x, y, w, h, selected, dimmed, playerColor, iconSize)
  local C = Config.COLORS
  local g = love.graphics
  if selected then y = y - 3 end
  UI.panel(x, y, w, h, selected and Config.ART.ui.panelLight or Config.ART.ui.panel)
  local a = dimmed and 0.35 or 1
  local def, level = card.def, card.level
  Upgrades.drawIcon(def, level, x + w * 0.5, y + 8 + iconSize * 0.5, iconSize, a)
  local gc = Upgrades.color(def)
  cardColor[1], cardColor[2], cardColor[3], cardColor[4] = gc[1], gc[2], gc[3], a
  local ty = y + 14 + iconSize
  UI.text("titleSmall", Upgrades.cardTitle(def, level), x + 2, ty, cardColor, w - 4, "center")
  -- Stacking stats: which level this card gives, in the top-right corner.
  local count = Upgrades.count(def, level)
  if count then UI.text("body", count, x, y + 5, cardColor, w - 6, "right") end
  local tc = C.text
  cardColor[1], cardColor[2], cardColor[3], cardColor[4] = tc[1], tc[2], tc[3], a
  UI.text("body", Upgrades.desc(def, level), x + 5, ty + 14, cardColor, w - 10, "center")
  if selected then
    g.setColor(playerColor[1], playerColor[2], playerColor[3], 1)
    g.setLineWidth(2)
    g.rectangle("line", x - 1, y - 1, w + 2, h + 2)
    g.setLineWidth(1)
  end
  g.setColor(1, 1, 1, 1)
end

-- One player's window: tab, header, the cards and (once picked) PRONTO.
local function drawSide(self, i, x, y, w, h, cardW, gap, iconSize, single)
  local C = Config.COLORS
  local world = self.world
  local p = world.players[i]
  local s = picks[i]
  -- Tab titles stay unaccented (see Config.ART.ui.tabH).
  local title
  if single then
    title = self.boss and S.up_title_boss or S.up_title
  else
    title = string.format(self.boss and S.up_title_p_boss or S.up_title_p, i)
  end
  local top = UI.window(x, y, w, h, title, single and Config.ART.ui.neutral or p.color)
  UI.text("body", self.boss and S.up_pick_boss or S.up_pick, x, top + 6, C.textDim, w, "center")

  local total = s.n * cardW + (s.n - 1) * gap
  local cx = x + (w - total) * 0.5
  local cy = top + 22
  local cardH = y + h - cy - 24   -- leaves room for PRONTO under the cards
  for k = 1, s.n do
    local bx = cx + (k - 1) * (cardW + gap)
    local selected = k == s.cursor
    drawCard(offers[i][k], bx, cy, cardW, cardH, selected, s.confirmed and not selected,
      p.color, iconSize)
    Touch.button(CARD_ACTIONS[i][k], bx, cy, cardW, cardH)
  end
  if s.confirmed then
    UI.text("title", S.ready, x, y + h - 18, p.color, w, "center")
  end
end

function Upgrade:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local world = self.world
  local h = 160
  local y = math.floor(Config.HUD_H + (H - Config.HUD_H - h) * 0.5) - 10
  if world.playerCount >= 2 then
    local w = 304
    drawSide(self, 1, 8, y, w, h, 92, 6, 22, false)
    drawSide(self, 2, W - w - 8, y, w, h, 92, 6, 22, false)
  else
    local w = 420
    drawSide(self, 1, math.floor((W - w) * 0.5), y, w, h, 124, 12, 28, true)
  end

  local touch = Input.usingTouch()
  UI.text("body", touch and S.up_hint_touch or S.up_hint, 0, y + h + 10, C.text, W, "center")
  love.graphics.setColor(1, 1, 1, 1)
end

return Upgrade
