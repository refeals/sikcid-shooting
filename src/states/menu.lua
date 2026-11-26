-- Main menu: the title screen, first thing after the boot.
--
--   JOGAR     -> the lobby, with the device that picked it already Player 1
--   OPÇÕES    -> src/states/options.lua (pushed: back here on BACK)
--   CRÉDITOS  -> src/states/credits.lua (pushed)
--   SAIR      -> quits (not in the browser, which has no quit)
--
-- Any device navigates (src/nav.lua): up/down move, START or A confirm. BACK
-- does nothing here (holding SELECT still quits, on every screen). On the
-- touch screen a tap on an item picks it. The cursor starts on JOGAR every
-- time the menu is entered; coming back from a pushed screen keeps it.

local Config = require("src.config")
local Input  = require("src.input")
local Touch  = require("src.touch")
local State  = require("src.state")
local Audio  = require("src.audio")
local Music  = require("src.music")
local UI     = require("src.ui")
local Nav    = require("src.nav")
local Background = require("src.background")

local Menu = {}

-- `action`: the touch button of the item (built once below).
local ITEMS = {
  { id = "play",    label = "JOGAR" },
  { id = "options", label = "OPÇÕES" },
  { id = "credits", label = "CRÉDITOS" },
  { id = "quit",    label = "SAIR", desktopOnly = true },
}
for i = 1, #ITEMS do ITEMS[i].action = "menu_" .. ITEMS[i].id end

-- Items on screen (SAIR is left out in the browser).
local items = {}
for i = 1, #ITEMS do
  if not (ITEMS[i].desktopOnly and Config.WEB) then items[#items + 1] = ITEMS[i] end
end

local cursor = 1
local NO_TAB = { 0, 0, 0, 0 }   -- invisible tab: plain rows share the tab's text baseline

function Menu:enter()
  cursor = 1
  Background.setTheme(1)
  Music.play("menu")
  if Config.SMOKE then require("src.smoke").note("state", "menu") end
end

local function choose(item, device)
  if item.id == "play" then
    -- Lobby:enter binds the device (and plays the confirm sound).
    require("src.transition").start()
    State.switch(require("src.states.lobby"), device)
  elseif item.id == "options" then
    Audio.play("menu_confirm")
    State.push(require("src.states.options"))
  elseif item.id == "credits" then
    Audio.play("menu_confirm")
    State.push(require("src.states.credits"))
  elseif item.id == "quit" then
    love.event.quit()
  end
end

function Menu:update()
  for i = 1, #items do
    if Nav.tapped(items[i].action) then
      cursor = i
      choose(items[i], Input.touch)
      return
    end
  end
  local cmd, device = Nav.poll()
  if cmd == "up" then
    cursor = (cursor - 2) % #items + 1
    Audio.play("menu_move")
  elseif cmd == "down" then
    cursor = cursor % #items + 1
    Audio.play("menu_move")
  elseif cmd == "confirm" then
    choose(items[cursor], device)
  end
end

-- `covered`: another menu screen is on top (it draws the whole screen).
function Menu:draw(covered)
  if covered then return end
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local M = Config.MENU

  Background.draw()

  UI.text("big", "SIKCID SHOOTIN'", 0, M.titleY, C.text, W, "center")
  UI.text("body", "ARENA COOPERATIVA PARA 1-2 JOGADORES", 0, M.subtitleY, C.textDim, W, "center")

  local n = #items
  local pw, ph = M.listW, n * M.rowH + 2 * M.rowPad
  local px = math.floor((W - pw) * 0.5)
  UI.panel(px, M.listY, pw, ph)
  local rx, rw = px + M.rowPad, pw - 2 * M.rowPad
  for i = 1, n do
    local ry = M.listY + M.rowPad + (i - 1) * M.rowH
    if i == cursor then
      UI.tab(C.textWarn, items[i].label, rx, ry + 2, rw, M.rowH - 4, "title")
    else
      UI.tab(NO_TAB, items[i].label, rx, ry + 2, rw, M.rowH - 4, "title", C.text)
    end
    Touch.button(items[i].action, rx, ry, rw, M.rowH)
  end

  local hint = Input.usingTouch() and "TOQUE NUMA OPÇÃO"
    or "D-PAD OU SETAS ESCOLHEM   -   START, A OU ENTER CONFIRMA"
  UI.text("body", hint, 0, M.hintY, C.text, W, "center")
  UI.exitBar(W * 0.5, M.hintY + 16)
  love.graphics.setColor(1, 1, 1, 1)
end

return Menu
