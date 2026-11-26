-- OPÇÕES: one window of rows, pushed over the main menu.
--
-- Value rows change with left/right (on the touch screen, their < >
-- arrows); START/A on a value row steps it forward, wrapping (the volumes
-- only move with left/right). Every change applies at once (Options.set: the
-- menu music and the move sound already play at the new volume); the file is
-- written when the screen closes.
--
-- Action rows: TESTAR CONTROLES (the input test, pushed on top), RESTAURAR
-- PADRÕES (asks once more) and APAGAR RECORDES (asks twice). Moving off the
-- row or BACK cancels a pending question; a second BACK closes the screen.
--
-- Items a command line flag holds this session are dimmed, show the flag
-- and don't change (see src/options.lua). TELA CHEIA only exists on a PC.
--
-- IDIOMA comes first and its values are the languages' own names (ENGLISH,
-- ESPAÑOL, PORTUGUÊS), so a player who switched by mistake finds the way
-- back. Every label is read from src/i18n.lua as it is drawn: a switch
-- shows on this screen in the same frame.

local Config = require("src.config")
local Input  = require("src.input")
local Touch  = require("src.touch")
local State  = require("src.state")
local Audio  = require("src.audio")
local Save   = require("src.save")
local UI     = require("src.ui")
local Assets = require("src.assets")
local Nav    = require("src.nav")
local Opts   = require("src.options")
local I18n   = require("src.i18n")
local Background = require("src.background")

local OptionsScreen = {}

local O = Config.OPTIONS
local L = Config.MENU.options
local S = I18n.S

-- Value rows: "choice" steps through `choices` (left = less, right = more;
-- per choice, `names` holds the text as is and `namesKey` the src/lang key
-- of a list of names; `fonts` the font role), "volume" goes 0..O.volumeSteps.
-- Action rows have an `id`; `asks` is the src/lang key of the questions
-- before it runs. `label` is a src/lang key too.
local SHAKE_NAMES, SHAKE_FONTS = {}, {}
for i = 1, #O.shakeSteps do
  local s = O.shakeSteps[i]
  -- Numbers in the digits font: Rocket Square draws "0" as a box. The 0 is
  -- a word (S.opt_off, see valueName).
  SHAKE_NAMES[i] = s ~= 0 and (s .. "%")
  SHAKE_FONTS[i] = s == 0 and "title" or "digits"
end

local ROWS = {
  { key = "lang", label = "opt_lang", kind = "choice",
    choices = I18n.CODES, names = I18n.NATIVE },
  { key = "fx", label = "opt_fx", kind = "choice",
    choices = { "off", "low", "high" }, namesKey = "opt_fx_levels" },
  { key = "music", label = "opt_music", kind = "volume" },
  { key = "sfx", label = "opt_sfx", kind = "volume" },
  { key = "shake", label = "opt_shake", kind = "choice",
    choices = O.shakeSteps, names = SHAKE_NAMES, fonts = SHAKE_FONTS },
  { key = "distortion", label = "opt_distortion", kind = "choice",
    choices = { false, true }, namesKey = "opt_distortion_values" },
  { key = "fullscreen", label = "opt_fullscreen", kind = "choice", pcOnly = true,
    choices = { false, true }, namesKey = "opt_no_yes" },
  { id = "test", label = "opt_test", kind = "action" },
  { id = "restore", label = "opt_restore", kind = "action", asks = "opt_restore_asks" },
  { id = "wipe", label = "opt_wipe", kind = "action", asks = "opt_wipe_asks" },
}

-- Text of choice `idx` of a value row.
local function valueName(r, idx)
  if r.namesKey then return S[r.namesKey][idx] end
  return r.names[idx] or S.opt_off   -- the shake's 0
end

-- Touch actions and volume digits, built once.
for i = 1, #ROWS do
  local r = ROWS[i]
  if r.kind == "action" then
    r.tap = "opt_" .. r.id
  else
    r.left, r.right = "opt_" .. r.key .. "_l", "opt_" .. r.key .. "_r"
  end
end
local VOLUME_TEXT = {}
for v = 0, O.volumeSteps do VOLUME_TEXT[v] = tostring(v) end

local rows = {}        -- rows on screen (built in enter: TELA CHEIA is PC only)
local cursor = 1
local ask = 0          -- questions answered on the cursor's action row
local status, statusT = nil, 0   -- feedback line, a src/lang key ("opt_restored")

local arrowColor = { 1, 1, 1, 1 }

local function indexOf(list, v)
  for i = 1, #list do
    if list[i] == v then return i end
  end
  return 1
end

function OptionsScreen:enter()
  for i = #rows, 1, -1 do rows[i] = nil end
  for i = 1, #ROWS do
    local r = ROWS[i]
    if not (r.pcOnly and not Opts.hasFullscreen()) then
      rows[#rows + 1] = r
      local flag = r.key and Opts.locked[r.key]
      r.lockTag = flag and ("(" .. flag .. ")") or nil
    end
  end
  cursor, ask, status, statusT = 1, 0, nil, 0
  if Config.SMOKE then require("src.smoke").bump("menus") end
end

local function moveTo(i)
  if i == cursor then return end
  cursor, ask, statusT = i, 0, 0
  Audio.play("menu_move")
end

-- Steps a value row by `dir`; `wrap` cycles past the ends (START/A).
local function step(r, dir, wrap)
  if Opts.locked[r.key] then
    Audio.play("menu_cancel")
    return
  end
  local v
  if r.kind == "volume" then
    if wrap then return end
    v = Opts.values[r.key] + dir
    if v < 0 or v > O.volumeSteps then return end
  else
    local n = #r.choices
    local i = indexOf(r.choices, Opts.values[r.key]) + dir
    if wrap then i = (i - 1) % n + 1 elseif i < 1 or i > n then return end
    v = r.choices[i]
  end
  Opts.set(r.key, v)
  Audio.play("menu_move")   -- after set: plays at the new effects volume
end

local function runAction(r)
  if r.id == "test" then
    Audio.play("menu_confirm")
    State.push(require("src.states.inputtest"), false)
    return
  end
  if ask < #S[r.asks] then
    ask = ask + 1
    Audio.play("menu_move")
    return
  end
  ask = 0
  if r.id == "restore" then
    Opts.restore()
    status = "opt_restored"
  elseif r.id == "wipe" then
    Save.clearRecords()
    status = "opt_wiped"
  end
  statusT = 2.0
  Audio.play("menu_confirm")
end

local function confirm(r)
  if r.kind == "action" then runAction(r) else step(r, 1, true) end
end

local function close()
  Opts.save()
  Audio.play("menu_cancel")
  State.pop()
end

function OptionsScreen:update(dt)
  if statusT > 0 then statusT = statusT - dt end

  -- Touch: arrows step their row, an action row's name runs it.
  for i = 1, #rows do
    local r = rows[i]
    if r.kind == "action" then
      if Nav.tapped(r.tap) then moveTo(i); confirm(r); return end
    else
      local l, rt = Nav.tapped(r.left), Nav.tapped(r.right)
      if l or rt then moveTo(i); step(r, l and -1 or 1); return end
    end
  end

  local cmd = Nav.poll()
  local n = #rows
  if cmd == "up" then
    moveTo((cursor - 2) % n + 1)
  elseif cmd == "down" then
    moveTo(cursor % n + 1)
  elseif cmd == "left" or cmd == "right" then
    local r = rows[cursor]
    if r.kind ~= "action" then step(r, cmd == "left" and -1 or 1) end
  elseif cmd == "confirm" then
    confirm(rows[cursor])
  elseif cmd == "back" then
    if ask > 0 then
      ask = 0
      Audio.play("menu_cancel")
    else
      close()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
-- Filled triangle pointing `dir` (-1 left, +1 right) with its tip at x.
local function arrow(x, cy, dir, color, alpha)
  local a = L.arrowSize
  arrowColor[1], arrowColor[2], arrowColor[3] = color[1], color[2], color[3]
  arrowColor[4] = alpha
  love.graphics.setColor(arrowColor)
  love.graphics.polygon("fill", x, cy, x - dir * a, cy - a, x - dir * a, cy + a)
end

local function drawValue(r, vx, ry, ink, locked, selected)
  local C = Config.COLORS
  local h, vw = L.rowH, L.valueW
  local v = Opts.values[r.key]
  local idx, count
  if r.kind == "volume" then
    idx, count = v + 1, O.volumeSteps + 1
  else
    idx, count = indexOf(r.choices, v), #r.choices
  end

  if not locked then
    local cy = ry + h * 0.5
    arrow(vx + 2, cy, -1, ink, idx > 1 and 1 or 0.25)
    arrow(vx + vw - 2, cy, 1, ink, idx < count and 1 or 0.25)
    -- Hit areas wider than the arrows (Touch adds its own margin too).
    Touch.button(r.left, vx - 6, ry, 22, h)
    Touch.button(r.right, vx + vw - 16, ry, 22, h)
  end

  local cx, cw = vx + 12, vw - 24
  if r.kind == "volume" then
    local fill = locked and C.textDim or (selected and C.text or C.textWarn)
    UI.bar(fill, cx, ry + math.floor((h - 6) * 0.5), L.barW, v / O.volumeSteps, 6)
    UI.digits("digits", VOLUME_TEXT[v], cx + L.barW, UI.midY("digits", ry, h), ink,
      cw - L.barW, "center")
  else
    local font = r.fonts and r.fonts[idx] or "title"
    if font == "digits" then
      UI.digits("digits", valueName(r, idx), cx, UI.midY("digits", ry, h), ink, cw, "center")
    else
      UI.textMid(font, valueName(r, idx), cx, ry, h, ink, cw, "center")
    end
  end
end

function OptionsScreen:draw()
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local M = Config.MENU

  Background.draw()
  UI.text("big", S.menu_options, 0, M.screenTitleY, C.text, W, "center")

  local n = #rows
  local wx = math.floor((W - L.w) * 0.5)
  UI.panel(wx, L.y, L.w, n * L.rowH + 2 * L.pad)
  local rx, rw = wx + L.pad, L.w - 2 * L.pad
  local titleFont = Assets.font("title")

  for i = 1, n do
    local r = rows[i]
    local ry = L.y + L.pad + (i - 1) * L.rowH
    local selected = i == cursor
    local locked = r.lockTag ~= nil
    if selected then UI.tab(C.textWarn, nil, rx, ry - L.hlRise, rw, L.rowH + L.hlRise + 1) end
    local ink = selected and UI.inkFor(C.textWarn) or (locked and C.textDim or C.text)

    local label = S[r.label]
    if selected and ask > 0 then label = S[r.asks][ask] end
    UI.textMid("title", label, rx + 8, ry, L.rowH, ink)
    if locked then
      UI.textMid("body", r.lockTag, rx + 16 + titleFont:getWidth(label), ry, L.rowH, ink)
    end

    if r.kind == "action" then
      Touch.button(r.tap, rx, ry, rw, L.rowH)
    else
      drawValue(r, rx + rw - L.valueW - 8, ry, ink, locked, selected)
    end
  end

  if status and statusT > 0 then
    UI.text("title", S[status], 0, L.statusY, C.textWarn, W, "center")
  end
  local hint = Input.usingTouch() and S.opt_hint_touch or S.opt_hint
  UI.text("body", hint, 0, M.hintY, C.text, W, "center")
  UI.exitBar(W * 0.5, M.hintY + 16)
  Nav.drawTouchBack()
  love.graphics.setColor(1, 1, 1, 1)
end

return OptionsScreen
