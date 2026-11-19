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
--
-- Seletor de cor: cada slot vinculado troca de cor com esquerda/direita e
-- sorteia com Y. A cor do outro jogador é sempre pulada, e a cor segue o
-- jogador se ele subir do slot 2 para o 1. A escolha vai para o save ao
-- começar a partida.

local Config = require("src.config")
local Input  = require("src.input")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Music  = require("src.music")
local State  = require("src.state")
local Player = require("src.entities.player")
local UI     = require("src.ui")
local Background = require("src.background")

local Lobby = {}

local PALETTE = Config.PLAYER_PALETTE
local COLOR_KEYS = { "color1", "color2" }

-- slots[i] = { device = <Device>, bindTimer = <segundos desde o vínculo>,
--              colorIndex = <índice em Config.PLAYER_PALETTE> }
local slots = { nil, nil }
local blink = 0

local function boundCount()
  return (slots[2] and 2) or (slots[1] and 1) or 0
end

local function isBound(device)
  return (slots[1] and slots[1].device == device)
      or (slots[2] and slots[2].device == device)
end

-- ---------------------------------------------------------------------------
-- Color picker
-- ---------------------------------------------------------------------------

-- Palette index held by the other slot (nil while it is empty).
local function otherColor(index)
  local o = slots[3 - index]
  return o and o.colorIndex or nil
end

-- Steps from `from` in `dir` (+1 / -1) to the next color nobody else holds.
local function nextFree(from, dir, taken)
  local n = #PALETTE
  local c = from
  for _ = 1, n do
    c = (c - 1 + dir) % n + 1
    if c ~= taken then return c end
  end
  return from
end

-- Random color that is neither the current one nor the other player's.
local function randomFree(current, taken)
  local n = #PALETTE
  local count = n - 1
  if taken and taken ~= current then count = count - 1 end
  if count <= 0 then return current end
  local r = math.random(count)
  for c = 1, n do
    if c ~= current and c ~= taken then
      r = r - 1
      if r == 0 then return c end
    end
  end
  return current
end

-- Publishes a slot's pick to Config.PLAYER_COLORS, which every player visual
-- reads (HUD, ships, shots, pause, game over).
local function applyColor(index)
  local s = slots[index]
  if s then Config.PLAYER_COLORS[index] = PALETTE[s.colorIndex].color end
end

local function setColor(index, c)
  local s = slots[index]
  if c == s.colorIndex then return end
  s.colorIndex = c
  applyColor(index)
  Audio.play("menu_move")
end

local function bind(index, device)
  -- Starts from the slot's saved pick, moved along if the other player has it.
  local c = Save.get(COLOR_KEYS[index])
  local taken = otherColor(index)
  if c == taken then c = nextFree(c, 1, taken) end
  slots[index] = { device = device, bindTimer = 0, colorIndex = c }
  device.boundTo = index
  applyColor(index)
  Audio.play("menu_confirm")
end

local function unbind(index)
  local s = slots[index]
  if not s then return end
  s.device.boundTo = nil
  slots[index] = nil
  -- Jogador 1 saiu: o Jogador 2 assume o slot 1, levando a cor dele.
  if index == 1 and slots[2] then
    slots[1] = slots[2]
    slots[2] = nil
    slots[1].device.boundTo = 1
    applyColor(1)
  end
  Audio.play("menu_cancel")
end

local function startGame()
  local n = boundCount()
  if n == 0 then return end
  local devices = { slots[1].device, slots[2] and slots[2].device or nil }
  local c1, c2 = slots[1].colorIndex, slots[2] and slots[2].colorIndex or nil
  Save.setColors(c1, c2)
  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.note("colors", c2 and string.format("%d/%d", c1, c2) or tostring(c1))
    if c1 == c2 then Smoke.bump("colorClash") end
  end
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
  -- Back from a match: the sky fades home to the first palette.
  Background.setTheme(1)
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

  -- Desvínculo, cor e início. BACK só desvincula se START não estiver
  -- segurado (senão atrapalharia o combo de saída back+start). O seletor
  -- espera o mesmo debounce do START: o d-pad que vinculou o Jogador 2 não
  -- troca a cor no mesmo toque.
  for i = 2, 1, -1 do
    local s = slots[i]
    if s and s.device.connected then
      local d = s.device
      local ready = s.bindTimer >= Config.BIND_DEBOUNCE
      if d:pressed("back") and not d:isDown("start") then
        unbind(i)
      elseif ready and d:pressed("left") then
        setColor(i, nextFree(s.colorIndex, -1, otherColor(i)))
      elseif ready and d:pressed("right") then
        setColor(i, nextFree(s.colorIndex, 1, otherColor(i)))
      elseif ready and d:pressed("random") then
        setColor(i, randomFree(s.colorIndex, otherColor(i)))
      elseif d:pressed("start") and ready then
        startGame()
        return
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Desenho
-- ---------------------------------------------------------------------------
-- Picker arrows (filled triangles: the Kenney fonts have no arrow glyphs)
-- on both sides of the ship preview.
local function drawArrows(cx, cy, color)
  local L = Config.LOBBY
  local a, gap = L.arrowSize, L.arrowGap
  love.graphics.setColor(color)
  love.graphics.polygon("fill", cx - gap, cy, cx - gap + a, cy - a, cx - gap + a, cy + a)
  love.graphics.polygon("fill", cx + gap, cy, cx + gap - a, cy - a, cx + gap - a, cy + a)
end

local function drawSlot(index, x, y, w, h)
  local C = Config.COLORS
  local s = slots[index]
  local color = Config.PLAYER_COLORS[index]

  local top = UI.window(x, y, w, h, "JOGADOR " .. index, s and color or Config.ART.ui.neutral)

  -- Ship preview in the slot color, gently swaying; grey while the slot is free.
  local cx, cy = x + w * 0.5, top + 24
  Player.drawShip(s and color or C.textDim, cx, cy,
    -math.pi / 2 + math.sin(blink * 1.5) * 0.4, 36, s and 1 or 0.6)

  if s then
    drawArrows(cx, cy, color)
    UI.text("body", PALETTE[s.colorIndex].name, x, top + 44, color, w, "center")
    if s.device.connected then
      UI.text("title", "PRONTO", x, top + 58, color, w, "center")
    else
      UI.text("title", "DESCONECTADO", x, top + 58, C.doorWarn, w, "center")
    end
    UI.text("body", s.device:displayName(), x + 6, top + 82, C.textDim, w - 12, "center")
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
  UI.digits("digits", tostring(value), x, y + 6, C.textWarn, w, "center")
end

function Lobby:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  Background.draw()

  UI.text("big", "SIKCID SHOOTIN'", 0, 14, C.text, W, "center")
  UI.text("body", "ARENA COOPERATIVA PARA 1-2 JOGADORES", 0, 44, C.textDim, W, "center")

  local sw, sh = 200, 130
  drawSlot(1, W * 0.5 - sw - 12, 60, sw, sh)
  drawSlot(2, W * 0.5 + 12, 60, sw, sh)

  -- Records: best solo, best single score in a duo, best duo total.
  local rw = 2 * sw + 24
  local rx = W * 0.5 - rw * 0.5
  local top = UI.window(rx, 198, rw, 62, "RECORDES", C.textWarn)
  local cw = rw / 3
  drawRecord("MELHOR SOLO", Save.get("solo"), rx, top + 8, cw)
  drawRecord("MELHOR EM DUPLA", Save.get("duo"), rx + cw, top + 8, cw)
  drawRecord("SOMA DA DUPLA", Save.get("coop"), rx + cw * 2, top + 8, cw)

  local bound = boundCount() > 0
  local hint = bound
    and "START PARA COMEÇAR   -   BACK PARA SAIR DO SLOT"
    or  "START PARA ENTRAR   -   TECLADO: ENTER"
  UI.text("body", hint, 0, 270, C.text, W, "center")
  if bound then
    UI.text("body", "D-PAD TROCA A COR   -   Y SORTEIA", 0, 284, C.text, W, "center")
  end
  if not Config.WEB then   -- the browser build has no quit (see Input)
    UI.text("body", "SEGURE SELECT PARA SAIR DO JOGO", 0, 298, C.textDim, W, "center")
    UI.exitBar(W * 0.5, 314)
  end

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
