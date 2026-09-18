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

local Pause = {}

local RESUME_DEBOUNCE = 0.2   -- ignora o START que abriu a pausa

function Pause:enter(world, mode, playerIndex)
  self.world = world
  self.mode = mode or "paused"
  self.playerIndex = playerIndex
  self.timer = 0
  self.confirmQuit = false   -- BACK pede confirmação antes de abandonar
  Audio.play("menu_confirm")
  if Config.SMOKE then
    require("src.smoke").bump(self.mode == "waiting" and "waits" or "pauses")
  end
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

  if self.mode == "waiting" then
    local idx = self.playerIndex or 1
    love.graphics.setColor(idx == 1 and C.p1 or C.p2)
    love.graphics.printf(string.format("AGUARDANDO CONTROLE DO JOGADOR %d", idx),
      0, H * 0.5 - 24, W, "center")
    love.graphics.setColor(C.textDim)
    love.graphics.printf("RECONECTE O CONTROLE PARA CONTINUAR", 0, H * 0.5 - 4, W, "center")
    love.graphics.printf("BACK ABANDONA A PARTIDA", 0, H * 0.5 + 14, W, "center")
  elseif self.confirmQuit then
    love.graphics.setColor(C.doorWarn)
    love.graphics.printf("ABANDONAR A PARTIDA?", 0, H * 0.5 - 24, W, "center")
    love.graphics.setColor(C.text)
    love.graphics.printf("BACK CONFIRMA   -   START CONTINUA JOGANDO", 0, H * 0.5 - 2, W, "center")
    love.graphics.setColor(C.textDim)
    love.graphics.printf("o progresso desta partida e perdido", 0, H * 0.5 + 16, W, "center")
  else
    love.graphics.setColor(C.text)
    love.graphics.printf("PAUSA", 0, H * 0.5 - 24, W, "center")
    love.graphics.setColor(C.textDim)
    love.graphics.printf("START CONTINUA   -   BACK ABANDONA A PARTIDA", 0, H * 0.5 - 2, W, "center")
    love.graphics.printf("SELECT + START (0.5s) SAI DO JOGO", 0, H * 0.5 + 16, W, "center")
  end

  -- Barra do combo de saída também visível aqui.
  local ex = Input.exitProgress()
  if ex > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W * 0.5 - 60, H * 0.5 + 40, 120 * ex, 4)
    love.graphics.setColor(C.hudLine)
    love.graphics.rectangle("line", W * 0.5 - 60.5, H * 0.5 + 39.5, 121, 5)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Pause
