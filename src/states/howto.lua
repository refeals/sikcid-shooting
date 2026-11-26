-- COMO JOGAR: two pages, pushed over the main menu with the device that
-- picked it (Menu passes it on).
--
--   page 1 -- the controls of that device: gamepad, keyboard or touch (the
--             smoke's scripted bot reads as a gamepad)
--   page 2 -- the rules: waves, combo, rest, upgrades, sub-bosses, boss,
--             with their numbers taken from Config (formatted once)
--
-- Left/right (on the touch screen, the arrows at the window's sides) turn
-- the page, without wrapping. START/A on page 1 turns to page 2 and on page
-- 2 closes; BACK (VOLTAR) closes from either. The power-ups stay with the
-- match briefing, which lists them.

local Config = require("src.config")
local Input  = require("src.input")
local Touch  = require("src.touch")
local State  = require("src.state")
local Audio  = require("src.audio")
local UI     = require("src.ui")
local Nav    = require("src.nav")
local Assets = require("src.assets")
local Background = require("src.background")

local HowTo = {}

local PAGES = 2
local PAGE_TEXT = {}   -- "1/2", "2/2"
for i = 1, PAGES do PAGE_TEXT[i] = i .. "/" .. PAGES end

-- Controls per device kind: { action, binding[, pcOnly] } rows and a note
-- line under them. `pcOnly` rows (quitting) don't exist in the browser.
local CONTROLS = {
  gamepad = {
    title = "CONTROLE",
    rows = {
      { "MOVER", "ANALÓGICO ESQUERDO" },
      { "MIRAR", "ANALÓGICO DIREITO" },
      { "ATIRAR", "AUTOMÁTICO" },
      { "DASH", "RB, LB OU B" },
      { "PAUSAR", "START OU BACK" },
      { "COR DA NAVE (LOBBY)", "D-PAD, Y SORTEIA" },
      { "SAIR DO JOGO", "SEGURAR SELECT", pcOnly = true },
    },
    note = "MIRAR É OPCIONAL: SEM MIRA, A NAVE ATIRA SOZINHA NO INIMIGO MAIS PERTO. O D-PAD TAMBÉM MIRA.",
  },
  keyboard = {
    title = "TECLADO",
    rows = {
      { "MOVER", "WASD" },
      { "MIRAR", "SETAS" },
      { "ATIRAR", "AUTOMÁTICO" },
      { "DASH", "SHIFT" },
      { "PAUSAR", "ENTER OU ESC" },
      { "COR DA NAVE (LOBBY)", "A/D, R SORTEIA" },
      { "SAIR DO JOGO", "SEGURAR ESC", pcOnly = true },
    },
    note = "MIRAR É OPCIONAL: SEM MIRA, A NAVE ATIRA SOZINHA NO INIMIGO MAIS PERTO.",
  },
  touch = {
    title = "TELA DE TOQUE",
    rows = {
      { "MOVER", "METADE ESQUERDA" },
      { "MIRAR", "METADE DIREITA" },
      { "ATIRAR", "AUTOMÁTICO" },
      { "DASH", "BOTÃO DASH" },
      { "PAUSAR", "BOTÃO DE PAUSA" },
      { "COR DA NAVE (LOBBY)", "SETAS DO SLOT" },
    },
    note = "ONDE O DEDO ENCOSTA VIRA O CENTRO DO ANALÓGICO. SEM DEDO NA DIREITA, A NAVE MIRA SOZINHA.",
  },
}

-- Rows on screen per kind (the pcOnly ones left out in the browser).
for _, c in pairs(CONTROLS) do
  c.shown = {}
  for i = 1, #c.rows do
    if not (c.rows[i].pcOnly and Config.WEB) then c.shown[#c.shown + 1] = c.rows[i] end
  end
end

-- "2,5" (PT-BR decimal comma); whole numbers without decimals.
local function num(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return (string.format("%.1f", v):gsub("%.", ","))
end

-- { heading, text }: headings in the Rocket Square font, which draws "0" as
-- a box, so they carry no digits; the numbers go in the text.
local RULES
local function buildRules()
  local CB, S = Config.COMBO, Config.SUBBOSS
  RULES = {
    { "WAVES", "OS INIMIGOS ENTRAM PELAS QUATRO PORTAS, EM LOTES (A PORTA PISCA ANTES). "
      .. "A WAVE ACABA QUANDO NÃO SOBRA NINGUÉM." },
    { "COMBO", string.format("CADA ABATE RENOVA UMA JANELA DE %s S. A CADA %d ABATES SEGUIDOS, "
      .. "O MULTIPLICADOR DOS PONTOS SOBE UM DEGRAU, ATÉ X%d.", num(CB.window), CB.perMult, CB.maxMult) },
    { "RESPIRO", string.format("ENTRE AS WAVES: BÔNUS, UM POWER-UP GARANTIDO E %s S DE RESPIRO, "
      .. "COM OS TIMERS DE COMBO E DE POWER-UP PARADOS.", num(Config.WAVE.restTime)) },
    { "UPGRADES", string.format("A CADA %d WAVES, CADA JOGADOR ESCOLHE UM UPGRADE PERMANENTE, "
      .. "QUE VALE ATÉ O FIM DA PARTIDA.", Config.UPGRADES.every) },
    { "SUB-BOSS", string.format("NAS WAVES %d, %d, %d... UM SUB-BOSS ENTRA NO MEIO DA WAVE "
      .. "E DEIXA POWER-UPS AO CAIR.", S.offset, S.offset + S.every, S.offset + 2 * S.every) },
    { "BOSS", string.format("A CADA %d WAVES, UMA WAVE DE BOSS. CADA UM É MAIS FORTE QUE O ANTERIOR.",
      Config.BOSS.every) },
  }
end

local page = 1
local controls = CONTROLS.gamepad
local arrowColor = { 1, 1, 1, 1 }

function HowTo:enter(device)
  page = 1
  local kind = device and device.kind
  controls = CONTROLS[kind] or CONTROLS.gamepad   -- "scripted" (smoke) too
  if not RULES then
    buildRules()
    -- Lines each rule's text wraps into (the font exists by now).
    local H = Config.MENU.howto
    local font = Assets.font("body")
    for i = 1, #RULES do
      local _, lines = font:getWrap(RULES[i][2], H.w - 2 * H.pad)
      RULES[i].lines = #lines
    end
  end
  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.bump("menus")
    Smoke.note("state", "howto")
  end
end

local function close()
  Audio.play("menu_cancel")
  State.pop()
end

local function turn(dir)
  local p = page + dir
  if p < 1 or p > PAGES then return end
  page = p
  Audio.play("menu_move")
  if Config.SMOKE then require("src.smoke").bump("pages") end
end

function HowTo:update()
  local prev, nxt = Nav.tapped("howto_prev"), Nav.tapped("howto_next")
  if prev or nxt then
    turn(prev and -1 or 1)
    return
  end
  local cmd = Nav.poll()
  if cmd == "left" then
    turn(-1)
  elseif cmd == "right" then
    turn(1)
  elseif cmd == "confirm" then
    if page < PAGES then turn(1) else close() end
  elseif cmd == "back" then
    close()
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
-- Page arrow pointing `dir` (-1 left, +1 right) with its tip at x, plus its
-- touch button.
local function pageArrow(x, cy, dir, enabled, action)
  local H = Config.MENU.howto
  local a = H.arrowSize
  local c = Config.COLORS.text
  arrowColor[1], arrowColor[2], arrowColor[3] = c[1], c[2], c[3]
  arrowColor[4] = enabled and 1 or 0.25
  love.graphics.setColor(arrowColor)
  love.graphics.polygon("fill", x, cy, x - dir * a, cy - a, x - dir * a, cy + a)
  -- Hit area centered on the triangle, wider than it.
  local hx = x - dir * a * 0.5 - H.arrowHitW * 0.5
  Touch.button(action, hx, cy - H.arrowHitH * 0.5, H.arrowHitW, H.arrowHitH)
end

local function drawControls(x, top)
  local C = Config.COLORS
  local H = Config.MENU.howto
  local rows = controls.shown
  local lx = x + H.pad
  local bx = lx + H.labelW + H.colGap
  local y = top + H.pad * 0.5
  for i = 1, #rows do
    local r = rows[i]
    UI.textMid("titleSmall", r[1], lx, y, H.rowH, C.textWarn, H.labelW, "right")
    UI.textMid("title", r[2], bx, y, H.rowH, C.text)
    y = y + H.rowH
  end
  UI.text("body", controls.note, lx, y + H.noteGap, C.textDim, H.w - 2 * H.pad, "center")
end

local function drawRules(x, top)
  local C = Config.COLORS
  local H = Config.MENU.howto
  local w = H.w - 2 * H.pad
  local lx = x + H.pad
  local y = top + H.pad * 0.5
  for i = 1, #RULES do
    local r = RULES[i]
    UI.text("titleSmall", r[1], lx, y, C.textWarn, w, "left")
    y = y + H.headH
    UI.text("body", r[2], lx, y, C.text, w, "left")
    y = y + r.lines * H.lineH + H.ruleGap
  end
end

function HowTo:draw()
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local M = Config.MENU
  local H = M.howto

  Background.draw()
  UI.text("big", "COMO JOGAR", 0, M.screenTitleY, C.text, W, "center")

  local x = math.floor((W - H.w) * 0.5)
  local top = UI.window(x, H.y, H.w, H.h, page == 1 and controls.title or "REGRAS", C.textWarn)
  if page == 1 then drawControls(x, top) else drawRules(x, top) end

  local cy = H.y + H.h * 0.5
  pageArrow(x - H.arrowX, cy, -1, page > 1, "howto_prev")
  pageArrow(x + H.w + H.arrowX, cy, 1, page < PAGES, "howto_next")
  UI.digits("digits", PAGE_TEXT[page], 0, H.pageY, C.textDim, W, "center")

  local hint = Input.usingTouch() and "TOQUE NAS SETAS PARA MUDAR A PÁGINA"
    or "D-PAD OU SETAS: PÁGINA   -   START: AVANÇA   -   BACK OU B: VOLTA"
  UI.text("body", hint, 0, M.hintY, C.text, W, "center")
  UI.exitBar(W * 0.5, M.hintY + 16)
  Nav.drawTouchBack()
  love.graphics.setColor(1, 1, 1, 1)
end

return HowTo
