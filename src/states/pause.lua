-- Overlay de pausa. Empilhado sobre o game (que continua sendo desenhado
-- por baixo, congelado).
--
-- Dois modos:
--   "paused"  -- pausa normal: START retoma, BACK volta ao lobby
--   "waiting" -- um controle vinculado caiu: só retoma quando ele voltar
--                (o Batocera reconecta com o mesmo GUID, então o vínculo é
--                preservado por Input.addJoystick)

local Config = require("src.config")
local Input  = require("src.input")
local Touch  = require("src.touch")
local State  = require("src.state")
local Audio  = require("src.audio")
local Music  = require("src.music")
local UI     = require("src.ui")
local Screen = require("src.screen")
local S      = require("src.i18n").S

local Pause = {}

local RESUME_DEBOUNCE = 0.2   -- ignora o START que abriu a pausa

function Pause:enter(world, mode, playerIndex)
  self.world = world
  self.mode = mode or "paused"
  self.playerIndex = playerIndex
  self.timer = 0
  self.confirmQuit = false   -- BACK pede confirmação antes de abandonar
  Screen.setShake(0, 0)      -- the frozen arena must not stay offset
  Music.duck(true)           -- música abaixa, não para
  Audio.play("menu_confirm")
  if Config.SMOKE then
    require("src.smoke").bump(self.mode == "waiting" and "waits" or "pauses")
  end
  -- Each player's permanent upgrades, spelled out (built once per pause).
  local Upgrades = require("src.systems.upgrades")
  self.upgradeText, self.anyUpgrades = {}, false
  for i = 1, world.playerCount do
    local p = world.players[i]
    local parts = {}
    for k = 1, #p.upgradeOrder do
      local id = p.upgradeOrder[k]
      parts[k] = Upgrades.label(Upgrades.byId(id), p.upgrades[id])
    end
    self.upgradeText[i] = #parts > 0 and table.concat(parts, ",  ") or S.pause_none
    if #parts > 0 then self.anyUpgrades = true end
  end
end

function Pause:leave()
  Music.duck(false)
end

-- Devolve o primeiro jogador cujo device caiu (ou nil).
local function disconnectedPlayer(world)
  for i = 1, world.playerCount do
    local d = world.players[i].device
    if d and not d.connected then return i end
  end
  return nil
end

function Pause:update(dt)
  self.timer = self.timer + dt
  local world = self.world

  if self.mode == "waiting" then
    -- Retoma sozinho assim que todos os controles estiverem de volta.
    local missing = disconnectedPlayer(world)
    if not missing then
      State.pop()
      return
    end
    self.playerIndex = missing
    -- Com o controle fora, só resta desistir: BACK de qualquer device.
    local quitter = Input.find(function(d) return d:pressed("back") and not d:isDown("start") end)
    if quitter and self.timer > RESUME_DEBOUNCE then
      require("src.transition").start()   -- wipe back to the lobby
      State.reset(require("src.states.lobby"))
    end
    return
  end

  -- Pausa normal: se um controle cair agora, vira espera.
  if disconnectedPlayer(world) then
    self.mode = "waiting"
    self.timer = 0
    return
  end

  if self.timer < RESUME_DEBOUNCE then return end

  for i = 1, world.playerCount do
    local d = world.players[i].device
    if d and d.connected then
      if d:pressed("start") then
        if self.confirmQuit then
          -- START cancela o pedido de abandono antes de retomar.
          self.confirmQuit = false
          Audio.play("menu_cancel")
        else
          Audio.play("menu_confirm")
          State.pop()
        end
        return
      elseif d:pressed("back") and not d:isDown("start") then
        if self.confirmQuit then
          Audio.play("menu_confirm")
          require("src.transition").start()   -- wipe back to the lobby
          State.reset(require("src.states.lobby"))
        else
          self.confirmQuit = true
          Audio.play("menu_move")
        end
        return
      end
    end
  end
end

function Pause:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- One window, three modes: tab color says whose problem it is.
  local title, tab, headline, headColor, line1, line2
  if self.mode == "waiting" then
    local idx = self.playerIndex or 1
    title, tab = S.pause_disconnected, Config.PLAYER_COLORS[idx]
    headline, headColor = string.format(S.pause_waiting, idx), Config.PLAYER_COLORS[idx]
    line1 = S.pause_reconnect
    line2 = S.pause_back_quits
  elseif self.confirmQuit then
    -- No accents in tab titles: they would sit on the tab's bevel (see
    -- Config.ART.ui.tabH).
    title, tab = S.pause_confirm, C.doorWarn
    headline, headColor = S.pause_quit_ask, C.doorWarn
    line1 = S.pause_confirm_hint
    line2 = S.pause_lost
  else
    -- No tab: it would just repeat the big headline.
    title, tab = nil, nil
    headline, headColor = S.pause_title, C.text
    line1 = S.pause_hint
    -- The browser build has no quit (see Input).
    line2 = not Config.WEB and S.hold_select_quit or nil
  end

  -- Touch: a tap anywhere is START; BACK gets its own button under the window.
  local touch = Input.usingTouch()
  local backLabel = nil
  if touch then
    if self.mode == "waiting" then
      line2, backLabel = nil, S.pause_quit_button
    elseif self.confirmQuit then
      line1, backLabel = S.pause_confirm_tap, S.pause_confirm
    else
      line1, line2, backLabel = S.pause_tap, nil, S.pause_quit_button
    end
  end

  local pw, ph = 360, 102
  local px, py = math.floor((W - pw) * 0.5), math.floor((H - ph) * 0.5)
  local top = UI.window(px, py, pw, ph, title, tab)
  -- Rocket Square is wide: only the short S.pause_title fits the big size.
  local big = self.mode ~= "waiting" and not self.confirmQuit
  UI.text(big and "big" or "title", headline, px, top + (big and 8 or 14), headColor, pw, "center")
  UI.text("body", line1, px, top + 44, C.text, pw, "center")
  if line2 then UI.text("body", line2, px, top + 60, C.textDim, pw, "center") end

  if backLabel then
    local bw, bh = 140, 20
    local bx, by = math.floor((W - bw) * 0.5), py + ph + 14
    UI.tab(C.doorWarn, backLabel, bx, by, bw, bh, "titleSmall", C.text)
    Touch.button("back", bx, by, bw, bh)
  end

  UI.exitBar(W * 0.5, py + ph + 10)

  -- Permanent upgrades so far, per player in their color (2P: two columns).
  if self.anyUpgrades and self.mode ~= "waiting" then
    local n = self.world.playerCount
    local uw, uh = 440, 50
    local ux, uy = math.floor((W - uw) * 0.5), py + ph + 40
    local utop = UI.window(ux, uy, uw, uh, S.upgrades_title)
    local colW = (uw - 16) / n
    for i = 1, n do
      UI.text("body", self.upgradeText[i], ux + 8 + (i - 1) * colW, utop + 6,
        Config.PLAYER_COLORS[i], colW - 8, n == 1 and "center" or "left")
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Pause
