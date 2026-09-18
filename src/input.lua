-- Camada de input por DEVICE. Nada aqui lê input "global": cada jogador
-- guarda uma referência ao seu device e só pergunta a ele.
--
-- Tipos de device:
--   "gamepad"  -- joystick com mapeamento SDL (Gamepad API), o caso do Batocera
--   "keyboard" -- fallback de desenvolvimento no PC (jogador 1)
--   "scripted" -- input sintético do modo --smoke
--
-- Ações lógicas: "start", "back", "fire".

local Config = require("src.config")
local Util   = require("src.util")

local Input = {
  devices = {},     -- todos os devices conhecidos (inclui desconectados)
  count = 0,
  keyboard = nil,
  scripted = nil,
  quitRequested = false,
  -- Joysticks que o SDL viu mas não sabe mapear como gamepad. Não viram
  -- device (eixos crus não são portáveis), mas ficam listados aqui para a
  -- tela de teste de input mostrar o problema em vez de ignorar em silêncio.
  unmapped = {},
  unmappedCount = 0,
}

local Device = {}
Device.__index = Device

-- Botões varridos para detectar "qualquer botão" no lobby.
local ANY_BUTTONS = {
  "a", "b", "x", "y", "leftshoulder", "rightshoulder",
  "leftstick", "rightstick", "dpup", "dpdown", "dpleft", "dpright",
}

-- Teclas equivalentes no fallback de teclado.
local KEY_MAP = {
  start = { "return", "kpenter" },
  back  = { "escape" },
  fire  = { "space" },
}

-- ---------------------------------------------------------------------------
-- Deadzone radial: aplicada ao MÓDULO do vetor e renormalizada, para que a
-- velocidade máxima seja a mesma em todas as direções.
-- ---------------------------------------------------------------------------
local function applyDeadzone(x, y)
  local dz = Config.DEADZONE
  local nx, ny, len = Util.normalize(x, y)
  if len <= dz then return 0, 0 end
  local m = (len - dz) / (1 - dz)
  if m > 1 then m = 1 end
  return nx * m, ny * m
end

-- ---------------------------------------------------------------------------
-- Device
-- ---------------------------------------------------------------------------
local function newDevice(kind, joystick)
  local d = setmetatable({
    kind = kind,
    joystick = joystick,
    connected = true,
    guid = joystick and joystick:getGUID() or kind,
    index = joystick and joystick:getID() or 0,
    down = {},       -- estado atual por ação
    prev = {},       -- estado do frame anterior (edge detect)
    pending = {},    -- só para "scripted": estado a aplicar no próximo poll
    anyDown = false,
    anyPrev = false,
    exitTimer = 0,
    boundTo = nil,   -- índice do jogador que usa este device (1 ou 2)
  }, Device)
  return d
end

function Device:displayName()
  if self.kind == "keyboard" then return "TECLADO" end
  if self.kind == "scripted" then return "SMOKE BOT" end
  if not self.joystick then return "CONTROLE ?" end
  local name = self.joystick:getName() or "CONTROLE"
  if #name > 22 then name = name:sub(1, 22) end
  return string.format("%s #%d", name:upper(), self.index)
end

-- Lê o hardware e atualiza estados. Chamado uma vez por frame por Input.update.
function Device:poll(dt)
  local prev, down = self.prev, self.down
  for k, v in pairs(down) do prev[k] = v end
  self.anyPrev = self.anyDown

  local any = false
  if self.kind == "gamepad" and self.connected and self.joystick then
    local j = self.joystick
    down.start = j:isGamepadDown("start")
    down.back  = j:isGamepadDown("back") or j:isGamepadDown("guide")
    down.fire  = j:isGamepadDown("a") or (j:getGamepadAxis("triggerright") or 0) > 0.5
    for i = 1, #ANY_BUTTONS do
      if j:isGamepadDown(ANY_BUTTONS[i]) then any = true; break end
    end
    any = any or down.start or down.back
  elseif self.kind == "keyboard" then
    local kb = love.keyboard
    for action, keys in pairs(KEY_MAP) do
      local v = false
      for i = 1, #keys do
        if kb.isDown(keys[i]) then v = true; break end
      end
      down[action] = v
    end
    any = down.start or down.fire
      or kb.isDown("w") or kb.isDown("a") or kb.isDown("s") or kb.isDown("d")
  elseif self.kind == "scripted" then
    -- Estado vem do buffer `pending`, preenchido por Input.scriptPress antes
    -- do poll; copiar aqui (e não direto em `down`) preserva o edge detect.
    for k, v in pairs(self.pending) do down[k] = v end
    any = down.start or down.fire
  else
    down.start, down.back, down.fire = false, false, false
  end
  self.anyDown = any

  -- Combo de saída: back + start segurados juntos. No teclado, ESC sozinho
  -- também conta (o PC não tem "select"), mas só depois do hold completo.
  local comboHeld = down.back and down.start
  if self.kind == "keyboard" and down.back then comboHeld = true end
  if comboHeld then
    self.exitTimer = self.exitTimer + dt
  else
    self.exitTimer = 0
  end
end

function Device:isDown(action)
  return self.down[action] == true
end

function Device:pressed(action)
  return self.down[action] == true and self.prev[action] ~= true
end

function Device:anyPressed()
  return self.anyDown and not self.anyPrev
end

-- Progresso 0..1 do combo de saída (para o aviso no HUD).
function Device:exitProgress()
  return Util.clamp(self.exitTimer / Config.EXIT_HOLD, 0, 1)
end

-- Vetor de movimento (analógico esquerdo / WASD).
function Device:moveVector()
  if self.kind == "gamepad" then
    if not self.connected or not self.joystick then return 0, 0 end
    local j = self.joystick
    return applyDeadzone(j:getGamepadAxis("leftx") or 0, j:getGamepadAxis("lefty") or 0)
  elseif self.kind == "keyboard" then
    local kb = love.keyboard
    local x = (kb.isDown("d") and 1 or 0) - (kb.isDown("a") and 1 or 0)
    local y = (kb.isDown("s") and 1 or 0) - (kb.isDown("w") and 1 or 0)
    local nx, ny = Util.normalize(x, y)
    return nx, ny
  elseif self.kind == "scripted" then
    -- Passa pela mesma deadzone dos gamepads: o smoke nunca gera um vetor
    -- maior que 1, como um analógico de verdade.
    return applyDeadzone(self.moveX or 0, self.moveY or 0)
  end
  return 0, 0
end

-- Vetor de mira (analógico direito / setas). Fallback de d-pad fica em
-- dpadVector para que o player possa priorizar corretamente.
function Device:aimVector()
  if self.kind == "gamepad" then
    if not self.connected or not self.joystick then return 0, 0 end
    local j = self.joystick
    return applyDeadzone(j:getGamepadAxis("rightx") or 0, j:getGamepadAxis("righty") or 0)
  elseif self.kind == "keyboard" then
    local kb = love.keyboard
    local x = (kb.isDown("right") and 1 or 0) - (kb.isDown("left") and 1 or 0)
    local y = (kb.isDown("down") and 1 or 0) - (kb.isDown("up") and 1 or 0)
    local nx, ny = Util.normalize(x, y)
    return nx, ny
  elseif self.kind == "scripted" then
    return applyDeadzone(self.aimX or 0, self.aimY or 0)
  end
  return 0, 0
end

-- Fallback de mira para controles sem analógico direito.
function Device:dpadVector()
  if self.kind ~= "gamepad" or not self.connected or not self.joystick then return 0, 0 end
  local j = self.joystick
  local x = (j:isGamepadDown("dpright") and 1 or 0) - (j:isGamepadDown("dpleft") and 1 or 0)
  local y = (j:isGamepadDown("dpdown") and 1 or 0) - (j:isGamepadDown("dpup") and 1 or 0)
  local nx, ny = Util.normalize(x, y)
  return nx, ny
end

-- ---------------------------------------------------------------------------
-- Input (registro de devices)
-- ---------------------------------------------------------------------------
local function addDevice(d)
  Input.count = Input.count + 1
  Input.devices[Input.count] = d
  return d
end

function Input.load()
  Input.devices, Input.count = {}, 0
  Input.unmapped, Input.unmappedCount = {}, 0
  Input.quitRequested = false

  Input.keyboard = addDevice(newDevice("keyboard"))

  if Config.SMOKE then
    Input.scripted = { addDevice(newDevice("scripted")) }
    if Config.SMOKE_2P then
      Input.scripted[2] = addDevice(newDevice("scripted"))
    end
  end

  local sticks = love.joystick.getJoysticks()
  for i = 1, #sticks do Input.addJoystick(sticks[i]) end
end

function Input.addJoystick(joystick)
  -- Já conhecido? O LÖVE dispara joystickadded também para os controles que
  -- já estavam ligados no boot, ou seja, para os mesmos que Input.load
  -- enumerou. Sem esta checagem, UM controle vira DOIS devices e o lobby
  -- deixa o mesmo controle virar P1 e P2.
  for i = 1, Input.count do
    local d = Input.devices[i]
    if d.kind == "gamepad" and d.joystick == joystick then
      d.connected = true
      return d
    end
  end
  for i = 1, Input.unmappedCount do
    if Input.unmapped[i].joystick == joystick then return nil end
  end

  if not joystick:isGamepad() then
    local name = joystick:getName() or "?"
    print(string.format("[input] joystick sem mapeamento gamepad: %s (guid %s)",
      name, joystick:getGUID()))
    Input.unmappedCount = Input.unmappedCount + 1
    Input.unmapped[Input.unmappedCount] = {
      name = name,
      guid = joystick:getGUID(),
      axes = joystick:getAxisCount(),
      buttons = joystick:getButtonCount(),
      joystick = joystick,
    }
    return nil
  end
  -- Reconexão: reaproveita o device antigo do mesmo GUID (o jogador continua
  -- vinculado ao "seu" controle depois de um hotplug).
  local guid = joystick:getGUID()
  for i = 1, Input.count do
    local d = Input.devices[i]
    if d.kind == "gamepad" and d.guid == guid and not d.connected then
      d.joystick = joystick
      d.index = joystick:getID()
      d.connected = true
      d.exitTimer = 0
      return d
    end
  end
  return addDevice(newDevice("gamepad", joystick))
end

function Input.removeJoystick(joystick)
  -- Some também da lista de não-mapeados (swap-remove).
  for i = Input.unmappedCount, 1, -1 do
    if Input.unmapped[i].joystick == joystick then
      Input.unmapped[i] = Input.unmapped[Input.unmappedCount]
      Input.unmapped[Input.unmappedCount] = nil
      Input.unmappedCount = Input.unmappedCount - 1
    end
  end

  for i = 1, Input.count do
    local d = Input.devices[i]
    if d.kind == "gamepad" and d.joystick == joystick then
      d.connected = false
      d.joystick = nil
      d.exitTimer = 0
      for k in pairs(d.down) do d.down[k] = false end
      return d
    end
  end
  return nil
end

function Input.update(dt)
  for i = 1, Input.count do
    local d = Input.devices[i]
    d:poll(dt)
    if d.exitTimer >= Config.EXIT_HOLD then
      Input.quitRequested = true
    end
  end
end

-- Maior progresso de combo de saída entre todos os devices (aviso no HUD).
function Input.exitProgress()
  local best = 0
  for i = 1, Input.count do
    local p = Input.devices[i]:exitProgress()
    if p > best then best = p end
  end
  return best
end

-- Primeiro device (na ordem de registro) que satisfaz `predicate`.
-- Usado pelo lobby: "quem apertou start?", "quem apertou qualquer botão?".
function Input.find(predicate)
  for i = 1, Input.count do
    local d = Input.devices[i]
    if d.connected and predicate(d) then return d end
  end
  return nil
end

-- --------------------------------------------------------------------------
-- Suporte ao modo --smoke: injeta estado no device sintético.
-- --------------------------------------------------------------------------
function Input.scriptAxis(which, moveX, moveY, aimX, aimY)
  local d = Input.scripted and Input.scripted[which]
  if not d then return end
  d.moveX, d.moveY, d.aimX, d.aimY = moveX, moveY, aimX, aimY
end

function Input.scriptPress(which, action, value)
  local d = Input.scripted and Input.scripted[which]
  if not d then return end
  d.pending[action] = value and true or false
end

Input.Device = Device
return Input
