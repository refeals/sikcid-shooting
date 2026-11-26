-- CRÉDITOS: one fixed page, pushed over the main menu. Any confirm or BACK
-- (VOLTAR on the touch screen) goes back. Same text as the README credits.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")
local Audio  = require("src.audio")
local UI     = require("src.ui")
local Nav    = require("src.nav")
local Background = require("src.background")

local Credits = {}

-- { heading, line, line... } per section.
local SECTIONS = {
  { "MÚSICA",
    "MUSIC LOOP BUNDLE, DE ABSTRACTION (TALLBEARD STUDIOS) - CC0",
    "SUNBURN, CLOAK OF DARKNESS, NEVER MISS E CRUSHING IT" },
  { "ARTE, FONTES E SONS DE COMBATE",
    "KENNEY (KENNEY.NL) - CC0",
    "SPACE SHOOTER EXTENSION, SIMPLE SPACE, PLANETS, UI PACK (SCI-FI),",
    "KENNEY FONTS E SCI-FI SOUNDS" },
  { "DEMAIS EFEITOS SONOROS",
    "GERADOS COM O SFXR (SFXR.ME)" },
  { "FEITO COM",
    "LÖVE (LOVE2D.ORG) - VERSÃO WEB COM LOVE.JS (MIT)" },
}

function Credits:enter()
  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.bump("menus")
    Smoke.note("state", "credits")
  end
end

function Credits:update()
  local cmd = Nav.poll()
  if cmd == "back" or cmd == "confirm" then
    Audio.play("menu_cancel")
    State.pop()
  end
end

function Credits:draw()
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local M = Config.MENU

  Background.draw()
  UI.text("big", "CRÉDITOS", 0, M.screenTitleY, C.text, W, "center")

  local CR = M.credits
  local h = 2 * CR.gap
  for i = 1, #SECTIONS do
    h = h + CR.headH + (#SECTIONS[i] - 1) * CR.lineH + (i < #SECTIONS and CR.gap or 0)
  end
  local ww = M.options.w
  local wx = math.floor((W - ww) * 0.5)
  UI.panel(wx, M.options.y, ww, h)

  local y = M.options.y + CR.gap
  for i = 1, #SECTIONS do
    local s = SECTIONS[i]
    UI.text("titleSmall", s[1], wx, y, C.textWarn, ww, "center")
    y = y + CR.headH
    for k = 2, #s do
      UI.text("body", s[k], wx, y, C.text, ww, "center")
      y = y + CR.lineH
    end
    y = y + CR.gap
  end

  if not Input.usingTouch() then
    UI.text("body", "START OU BACK VOLTA", 0, M.hintY, C.text, W, "center")
  end
  UI.exitBar(W * 0.5, M.hintY + 16)
  Nav.drawTouchBack()
  love.graphics.setColor(1, 1, 1, 1)
end

return Credits
