-- RECORDES: one fixed page, pushed over the main menu. Any confirm or BACK
-- (VOLTAR on the touch screen) goes back.
--
-- Three windows: the score records (the same three as the lobby), the best
-- match (furthest wave solo and in a duo, longest combo) and this machine's
-- totals (every match, quit ones included; see Save.addPlayed). Values come
-- from src/save.lua and are formatted once, on entering.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")
local Audio  = require("src.audio")
local Save   = require("src.save")
local UI     = require("src.ui")
local Nav    = require("src.nav")
local Background = require("src.background")

local Records = {}

-- { label, save key[, format] } per column; rows of each window.
local SCORES = {
  { "MELHOR SOLO", "solo" },
  { "MELHOR EM DUPLA", "duo" },
  { "SOMA DA DUPLA", "coop" },
}
local BEST = {
  { "WAVE SOLO", "waveSolo" },
  { "WAVE EM DUPLA", "waveDuo" },
  { "MAIOR COMBO", "combo" },
}
local STATS_TOP = {
  { "PARTIDAS", "matches" },
  { "INIMIGOS ABATIDOS", "kills" },
  { "TEMPO JOGADO", "seconds", "time" },
}
local STATS_BOTTOM = {
  { "BOSSES", "bosses" },
  { "SUB-BOSSES", "subbosses" },
}
local LISTS = { SCORES, BEST, STATS_TOP, STATS_BOTTOM }

-- "14H 05M": hours, then minutes in two digits.
local function playTime(seconds)
  local m = math.floor(seconds / 60)
  return string.format("%dH %02dM", math.floor(m / 60), m % 60)
end

function Records:enter()
  for l = 1, #LISTS do
    local list = LISTS[l]
    for i = 1, #list do
      local c = list[i]
      local v = Save.get(c[2])
      c.text = c[3] == "time" and playTime(v) or tostring(v)
    end
  end
  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.bump("menus")
    Smoke.note("state", "records")
  end
end

function Records:update()
  local cmd = Nav.poll()
  if cmd == "back" or cmd == "confirm" then
    Audio.play("menu_cancel")
    State.pop()
  end
end

-- One row of label-over-value columns, `n` columns wide each (`list` may be
-- shorter: it is centered in the window).
local function drawRow(list, x, y, w, n)
  local C = Config.COLORS
  local R = Config.MENU.records
  local cw = w / n
  local x0 = x + (w - cw * #list) * 0.5
  for i = 1, #list do
    local c = list[i]
    local cx = x0 + (i - 1) * cw
    UI.text("body", c[1], cx, y + R.labelY, C.textDim, cw, "center")
    UI.digits("digits", c.text, cx, y + R.valueY, C.textWarn, cw, "center")
  end
end

function Records:draw()
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local M = Config.MENU
  local R = M.records

  Background.draw()
  UI.text("big", "RECORDES", 0, M.screenTitleY, C.text, W, "center")

  local x = math.floor((W - R.w) * 0.5)
  local y = R.y
  -- "PONTOS", not "PONTUAÇÃO": the tilde would touch the tab's top edge.
  local top = UI.window(x, y, R.w, R.h, "PONTOS", C.textWarn)
  drawRow(SCORES, x, top, R.w, 3)
  y = y + R.h + R.gap
  top = UI.window(x, y, R.w, R.h, "MELHOR PARTIDA", C.textWarn)
  drawRow(BEST, x, top, R.w, 3)
  y = y + R.h + R.gap
  top = UI.window(x, y, R.w, R.statsH, "ESTA MÁQUINA")
  drawRow(STATS_TOP, x, top, R.w, 3)
  drawRow(STATS_BOTTOM, x, top + R.rowGap, R.w, 3)

  if not Input.usingTouch() then
    UI.text("body", "START OU BACK VOLTA", 0, M.hintY, C.text, W, "center")
  end
  UI.exitBar(W * 0.5, M.hintY + 16)
  Nav.drawTouchBack()
  love.graphics.setColor(1, 1, 1, 1)
end

return Records
