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
  local color = index == 1 and C.p1 or C.p2
  local dim   = index == 1 and C.p1Dim or C.p2Dim

  love.graphics.setColor(s and dim or C.hudBg)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(s and color or C.hudLine)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)

  love.graphics.setColor(C.text)
  love.graphics.printf("JOGADOR " .. index, x, y + 8, w, "center")

  -- Preview do quadrado do jogador.
  local px, py = x + w * 0.5 - 10, y + 34
  love.graphics.setColor(s and color or C.textDim)
  love.graphics.rectangle("fill", px, py, 20, 20)

  if s then
    if s.device.connected then
      love.graphics.setColor(color)
      love.graphics.printf("PRONTO", x, y + 64, w, "center")
    else
      love.graphics.setColor(C.doorWarn)
      love.graphics.printf("DESCONECTADO", x, y + 64, w, "center")
    end
    love.graphics.setColor(C.textDim)
    love.graphics.printf(s.device:displayName(), x + 4, y + 82, w - 8, "center")
  else
    -- Pisca o convite para dar vida à tela.
    local a = 0.55 + 0.45 * math.sin(blink * 4)
    love.graphics.setColor(C.textDim[1], C.textDim[2], C.textDim[3], a)
    love.graphics.printf(index == 1 and "PRESSIONE START" or "PRESSIONE QUALQUER BOTAO",
      x + 6, y + 64, w - 12, "center")
  end
end

function Lobby:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  love.graphics.setColor(C.arenaBg)
  love.graphics.rectangle("fill", 0, 0, W, H)

  love.graphics.setColor(C.text)
  love.graphics.printf("SikCid Shootin'", 0, 26, W, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf("ARENA COOPERATIVA PARA 1-2 JOGADORES", 0, 46, W, "center")

  local sw, sh = 200, 110
  drawSlot(1, W * 0.5 - sw - 12, 90, sw, sh)
  drawSlot(2, W * 0.5 + 12, 90, sw, sh)

  -- Recordes: individual em 1P, individual em 2P e soma do coop.
  love.graphics.setColor(C.textWarn)
  love.graphics.printf(string.format("SOLO %d", Save.get("solo")),
    W * 0.5 - 300, 218, 190, "center")
  love.graphics.printf(string.format("DUPLA %d", Save.get("duo")),
    W * 0.5 - 95, 218, 190, "center")
  love.graphics.printf(string.format("COOP %d", Save.get("coop")),
    W * 0.5 + 110, 218, 190, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf("RECORDES: MELHOR SOLO  -  MELHOR EM DUPLA  -  MELHOR SOMA DA DUPLA",
    0, 234, W, "center")

  love.graphics.setColor(C.textDim)
  local hint = boundCount() == 0
    and "START PARA ENTRAR   -   TECLADO: ENTER"
    or  "START PARA COMECAR   -   BACK PARA SAIR DO SLOT"
  love.graphics.printf(hint, 0, 252, W, "center")
  love.graphics.printf("SEGURE SELECT PARA SAIR DO JOGO", 0, 272, W, "center")

  -- Barra do combo de saída.
  local p = Input.exitProgress()
  if p > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W * 0.5 - 60, 292, 120 * p, 4)
    love.graphics.setColor(C.hudLine)
    love.graphics.rectangle("line", W * 0.5 - 60.5, 291.5, 121, 5)
  end

  if Config.DEBUG then
    love.graphics.setColor(C.textDim)
    love.graphics.print(string.format("FPS %d  devices %d", love.timer.getFPS(), Input.count), 4, H - 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Expõe os slots para o modo smoke e para o game over.
function Lobby.getSlots()
  return slots
end

return Lobby
