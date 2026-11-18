-- Tela 1: seleção de jogadores.
--
-- Regras de vínculo:
--   1. Dois slots vazios, nenhum controle vinculado.
--   2. Primeiro device que apertar START vira o Jogador 1.
--   3. Esse MESMO device apertando START de novo inicia o jogo em 1 player.
--   4. QUALQUER botão de outro device vincula o Jogador 2; a partir daí START
--      de qualquer um dos dois inicia o jogo em 2 players.
--   5. BACK desvincula; se o Jogador 1 sai, o Jogador 2 assume o slot 1.
--   6. Debounce de Config.BIND_DEBOUNCE no START que acabou de vincular.

local Config = require("src.config")
local Input  = require("src.input")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Music  = require("src.music")
local State  = require("src.state")
local Player = require("src.entities.player")
local UI     = require("src.ui")
local Starfield = require("src.starfield")

local Lobby = {}

-- slots[i] = { device = <Device>, bindTimer = <segundos desde o vínculo> }
local slots = { nil, nil }
local blink = 0

local function boundCount()
  return (slots[2] and 2) or (slots[1] and 1) or 0
end

local function isBound(device)
  return (slots[1] and slots[1].device == device)
      or (slots[2] and slots[2].device == device)
end

local function bind(index, device)
  slots[index] = { device = device, bindTimer = 0 }
  device.boundTo = index
  Audio.play("menu_confirm")
end

local function unbind(index)
  local s = slots[index]
  if not s then return end
  s.device.boundTo = nil
  slots[index] = nil
  -- Jogador 1 saiu: o Jogador 2 assume o slot 1.
  if index == 1 and slots[2] then
    slots[1] = slots[2]
    slots[2] = nil
    slots[1].device.boundTo = 1
  end
  Audio.play("menu_cancel")
end

local function startGame()
  local n = boundCount()
  if n == 0 then return end
  local devices = { slots[1].device, slots[2] and slots[2].device or nil }
  Audio.play("menu_confirm")
  State.switch(require("src.states.game"), devices, n)
end

function Lobby:enter()
  -- Volta do game over com os slots preservados só enquanto os devices
  -- seguirem conectados; qualquer um desconectado é solto.
  for i = 2, 1, -1 do
    local s = slots[i]
    if s and (not s.device.connected) then unbind(i) end
  end
  for i = 1, 2 do
    if slots[i] then slots[i].bindTimer = Config.BIND_DEBOUNCE end
  end
  blink = 0
  Music.play("menu")
  if Config.SMOKE then require("src.smoke").note("state", "lobby") end
end

function Lobby:update(dt)
  blink = blink + dt
  for i = 1, 2 do
    local s = slots[i]
    if s then s.bindTimer = s.bindTimer + dt end
  end

  -- Vínculo de novos devices.
  if not slots[1] then
    local d = Input.find(function(dev) return dev:pressed("start") end)
    if d then bind(1, d) end
  elseif not slots[2] then
    local d = Input.find(function(dev)
      return not isBound(dev) and dev:anyPressed()
    end)
    if d then bind(2, d) end
  end

  -- Desvínculo e início. BACK só desvincula se START não estiver segurado
  -- (senão atrapalharia o combo de saída back+start).
  for i = 2, 1, -1 do
    local s = slots[i]
    if s and s.device.connected then
      if s.device:pressed("back") and not s.device:isDown("start") then
        unbind(i)
      elseif s.device:pressed("start") and s.bindTimer >= Config.BIND_DEBOUNCE then
        startGame()
        return
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Desenho
-- ---------------------------------------------------------------------------
local function drawSlot(index, x, y, w, h)
  local C = Config.COLORS
  local s = slots[index]
  local color = Config.PLAYER_COLORS[index]

  local top = UI.window(x, y, w, h, "JOGADOR " .. index, s and color or Config.ART.ui.neutral)

  -- Ship preview in the slot color, gently swaying; grey while the slot is free.
  Player.drawShip(s and color or C.textDim, x + w * 0.5, top + 28,
    -math.pi / 2 + math.sin(blink * 1.5) * 0.4, 36, s and 1 or 0.6)

  if s then
    if s.device.connected then
      UI.text("title", "PRONTO", x, top + 54, color, w, "center")
    else
      UI.text("title", "DESCONECTADO", x, top + 54, C.doorWarn, w, "center")
    end
    UI.text("body", s.device:displayName(), x + 6, top + 78, C.textDim, w - 12, "center")
  else
    -- Pulsing invitation to bring the screen to life.
    local a = 0.55 + 0.45 * math.sin(blink * 4)
    UI.text("body", index == 1 and "PRESSIONE START" or "PRESSIONE QUALQUER BOTÃO",
      x + 6, top + 60, { C.textDim[1], C.textDim[2], C.textDim[3], a }, w - 12, "center")
  end
end

-- One record column: label over its value.
local function drawRecord(label, value, x, y, w)
  local C = Config.COLORS
  UI.text("body", label, x, y, C.textDim, w, "center")
  UI.text("monoLarge", tostring(value), x, y + 6, C.textWarn, w, "center")
end

function Lobby:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  love.graphics.setColor(C.arenaBg)
  love.graphics.rectangle("fill", 0, 0, W, H)
  Starfield.draw()

  UI.text("big", "SIKCID SHOOTIN'", 0, 14, C.text, W, "center")
  UI.text("body", "ARENA COOPERATIVA PARA 1-2 JOGADORES", 0, 44, C.textDim, W, "center")

  local sw, sh = 200, 120
  drawSlot(1, W * 0.5 - sw - 12, 64, sw, sh)
  drawSlot(2, W * 0.5 + 12, 64, sw, sh)

  -- Records: best solo, best single score in a duo, best duo total.
  local rw = 2 * sw + 24
  local rx = W * 0.5 - rw * 0.5
  local top = UI.window(rx, 196, rw, 52, "RECORDES", C.textWarn)
  local cw = rw / 3
  drawRecord("MELHOR SOLO", Save.get("solo"), rx, top + 8, cw)
  drawRecord("MELHOR EM DUPLA", Save.get("duo"), rx + cw, top + 8, cw)
  drawRecord("SOMA DA DUPLA", Save.get("coop"), rx + cw * 2, top + 8, cw)

  local hint = boundCount() == 0
    and "START PARA ENTRAR   -   TECLADO: ENTER"
    or  "START PARA COMEÇAR   -   BACK PARA SAIR DO SLOT"
  UI.text("body", hint, 0, 266, C.text, W, "center")
  UI.text("body", "SEGURE SELECT PARA SAIR DO JOGO", 0, 282, C.textDim, W, "center")
  UI.exitBar(W * 0.5, 300)

  if Config.DEBUG then
    UI.text("body", string.format("FPS %d  devices %d", love.timer.getFPS(), Input.count), 4, H - 12, C.textDim)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Expõe os slots para o modo smoke e para o game over.
function Lobby.getSlots()
  return slots
end

return Lobby
