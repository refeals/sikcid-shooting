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
local State  = require("src.state")
local Audio  = require("src.audio")
local Music  = require("src.music")
local UI     = require("src.ui")
local Screen = require("src.screen")

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
    title, tab = "CONTROLE DESCONECTADO", Config.PLAYER_COLORS[idx]
    headline, headColor = string.format("AGUARDANDO O JOGADOR %d", idx), Config.PLAYER_COLORS[idx]
    line1 = "RECONECTE O CONTROLE PARA CONTINUAR"
    line2 = "BACK ABANDONA A PARTIDA"
  elseif self.confirmQuit then
    -- No accents in tab titles: they would sit on the tab's bevel (see
    -- Config.ART.ui.tabH).
    title, tab = "CONFIRMAR", C.doorWarn
    headline, headColor = "ABANDONAR A PARTIDA?", C.doorWarn
    line1 = "BACK CONFIRMA   -   START CONTINUA JOGANDO"
    line2 = "O PROGRESSO DESTA PARTIDA É PERDIDO"
  else
    -- No tab: it would just repeat the big headline.
    title, tab = nil, nil
    headline, headColor = "PAUSA", C.text
    line1 = "START CONTINUA   -   BACK ABANDONA A PARTIDA"
    line2 = "SEGURE SELECT PARA SAIR DO JOGO"
  end

  local pw, ph = 360, 102
  local px, py = math.floor((W - pw) * 0.5), math.floor((H - ph) * 0.5)
  local top = UI.window(px, py, pw, ph, title, tab)
  -- Rocket Square is wide: only the short "PAUSA" fits the big size.
  local big = self.mode ~= "waiting" and not self.confirmQuit
  UI.text(big and "big" or "title", headline, px, top + (big and 8 or 14), headColor, pw, "center")
  UI.text("body", line1, px, top + 44, C.text, pw, "center")
  UI.text("body", line2, px, top + 60, C.textDim, pw, "center")

  UI.exitBar(W * 0.5, py + ph + 10)
  love.graphics.setColor(1, 1, 1, 1)
end

return Pause
