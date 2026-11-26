-- COMO JOGAR: two pages, pushed over the main menu with the device that
-- picked it (Menu passes it on).
--
--   page 1 -- the controls of that device: gamepad, keyboard or touch (the
--             smoke's scripted bot reads as a gamepad)
--   page 2 -- the rules: waves, combo, rest, upgrades, sub-bosses, boss,
--             with their numbers taken from Config (formatted once per
--             language)
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
local I18n   = require("src.i18n")
local Background = require("src.background")

local HowTo = {}

local S = I18n.S

local PAGES = 2
local PAGE_TEXT = {}   -- "1/2", "2/2"
for i = 1, PAGES do PAGE_TEXT[i] = i .. "/" .. PAGES end

-- Controls per device kind: { action, binding[, pcOnly] } rows and a note
-- line under them, all src/lang keys. `pcOnly` rows (quitting) don't exist
-- in the browser.
local CONTROLS = {
  gamepad = {
    title = "howto_pad",
    rows = {
      { "act_move", "pad_move" },
      { "act_aim", "pad_aim" },
      { "act_fire", "bind_auto" },
      { "act_dash", "pad_dash" },
      { "act_pause", "pad_pause" },
      { "act_color", "pad_color" },
      { "act_quit", "pad_quit", pcOnly = true },
    },
    note = "pad_note",
  },
  keyboard = {
    title = "howto_keyboard",
    rows = {
      { "act_move", "kb_move" },
      { "act_aim", "kb_aim" },
      { "act_fire", "bind_auto" },
      { "act_dash", "kb_dash" },
      { "act_pause", "kb_pause" },
      { "act_color", "kb_color" },
      { "act_quit", "kb_quit", pcOnly = true },
    },
    note = "kb_note",
  },
  touch = {
    title = "howto_touch",
    rows = {
      { "act_move", "touch_move" },
      { "act_aim", "touch_aim" },
      { "act_fire", "bind_auto" },
      { "act_dash", "touch_dash" },
      { "act_pause", "touch_pause" },
      { "act_color", "touch_color" },
    },
    note = "touch_note",
  },
}

-- Rows on screen per kind (the pcOnly ones left out in the browser).
for _, c in pairs(CONTROLS) do
  c.shown = {}
  for i = 1, #c.rows do
    if not (c.rows[i].pcOnly and Config.WEB) then c.shown[#c.shown + 1] = c.rows[i] end
  end
end

-- { heading, text }: headings in the Rocket Square font, which draws "0" as
-- a box, so they carry no digits; the numbers go in the text. Built in the
-- current language, again only after a switch (I18n.version).
local RULES, rulesVersion
local function buildRules()
  local CB, SB = Config.COMBO, Config.SUBBOSS
  local num = I18n.num
  RULES = {
    { S.rule_waves_h, S.rule_waves },
    { S.rule_combo_h, string.format(S.rule_combo, num(CB.window), CB.perMult, CB.maxMult) },
    { S.rule_rest_h, string.format(S.rule_rest, num(Config.WAVE.restTime)) },
    { S.rule_upgrades_h, string.format(S.rule_upgrades, Config.UPGRADES.every) },
    { S.rule_subboss_h, string.format(S.rule_subboss, SB.offset, SB.offset + SB.every, SB.offset + 2 * SB.every) },
    { S.rule_boss_h, string.format(S.rule_boss, Config.BOSS.every) },
  }
  -- Lines each rule's text wraps into (the font exists by now).
  local H = Config.MENU.howto
  local font = Assets.font("body")
  for i = 1, #RULES do
    local _, lines = font:getWrap(RULES[i][2], H.w - 2 * H.pad)
    RULES[i].lines = #lines
  end
  rulesVersion = I18n.version
end

local page = 1
local controls = CONTROLS.gamepad
local arrowColor = { 1, 1, 1, 1 }

function HowTo:enter(device)
  page = 1
  local kind = device and device.kind
  controls = CONTROLS[kind] or CONTROLS.gamepad   -- "scripted" (smoke) too
  if rulesVersion ~= I18n.version then buildRules() end
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
    UI.textMid("titleSmall", S[r[1]], lx, y, H.rowH, C.textWarn, H.labelW, "right")
    UI.textMid("title", S[r[2]], bx, y, H.rowH, C.text)
    y = y + H.rowH
  end
  UI.text("body", S[controls.note], lx, y + H.noteGap, C.textDim, H.w - 2 * H.pad, "center")
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
  UI.text("big", S.menu_howto, 0, M.screenTitleY, C.text, W, "center")

  local x = math.floor((W - H.w) * 0.5)
  local top = UI.window(x, H.y, H.w, H.h, page == 1 and S[controls.title] or S.howto_rules, C.textWarn)
  if page == 1 then drawControls(x, top) else drawRules(x, top) end

  local cy = H.y + H.h * 0.5
  pageArrow(x - H.arrowX, cy, -1, page > 1, "howto_prev")
  pageArrow(x + H.w + H.arrowX, cy, 1, page < PAGES, "howto_next")
  UI.digits("digits", PAGE_TEXT[page], 0, H.pageY, C.textDim, W, "center")

  local hint = Input.usingTouch() and S.howto_hint_touch or S.howto_hint
  UI.text("body", hint, 0, M.hintY, C.text, W, "center")
  UI.exitBar(W * 0.5, M.hintY + 16)
  Nav.drawTouchBack()
  love.graphics.setColor(1, 1, 1, 1)
end

return HowTo
