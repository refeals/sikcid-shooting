-- Piloto automático do modo --smoke: injeta input sintético para exercitar
-- lobby, arena, waves e game over sem gamepad físico, e sai com código 0/1.
-- Usado na validação de cada etapa: `love . --smoke 15 ; echo $?`

local Config = require("src.config")
local Input  = require("src.input")

local Smoke = {
  t = 0,
  fpsMin = 9999,
  stats = {},          -- preenchido pelo jogo via Smoke.note/Smoke.bump
  nextEvent = 1,
}

-- Gamepad falso, criado em Smoke.reset quando --fakepad está ligado.
local pad = nil

-- Timeline: {tempo, device, ação, valor} para botões, ou {tempo, 0, "fn", fn}.
-- Um pulso de botão = press + release. O device 2 só existe com --smoke2p.
local EVENTS = {
  -- Regressão: o LÖVE reanuncia os controles já ligados no boot. Adicionar o
  -- MESMO joystick de novo não pode criar um segundo device (senão o mesmo
  -- controle vira P1 e P2 no lobby).
  { 0.20, 0, "fn", function()
      if pad then love.joystickadded(pad.j); love.joystickadded(pad.j) end
    end },
  { 0.40, 1, "start", true  },   -- vincula o Jogador 1
  { 0.50, 1, "start", false },
  { 0.80, 2, "fire",  true  },   -- qualquer botão do device 2 vincula o Jogador 2
  { 0.90, 2, "fire",  false },
  { 1.20, 1, "start", true  },   -- inicia a partida (debounce já passou)
  { 1.30, 1, "start", false },
  -- Abre e fecha a tela de teste de input (F5), exercitando push/pop da pilha.
  { 1.60, 0, "fn", function() love.keypressed("f5", "f5", false) end },
  { 1.80, 0, "fn", function() love.keypressed("f5", "f5", false) end },
  -- Pausa e retoma (START no jogo).
  { 4.00, 1, "start", true  },
  { 4.10, 1, "start", false },
  { 4.60, 1, "start", true  },
  { 4.70, 1, "start", false },
  -- Queda e volta do controle (só com --fakepad): deve abrir a tela
  -- "AGUARDANDO CONTROLE" e retomar sozinho na reconexão.
  { 6.00, 0, "fn", function()
      if pad then love.joystickremoved(pad.j) end
    end },
  { 7.50, 0, "fn", function()
      if pad then love.joystickadded(pad.j) end
    end },
  -- BACK durante o jogo abre a pausa; BACK de novo pede confirmação de
  -- abandono; START cancela a confirmação; START retoma a partida.
  { 8.00, 1, "back",  true  },
  { 8.10, 1, "back",  false },
  { 8.50, 1, "back",  true  },
  { 8.60, 1, "back",  false },
  { 9.00, 1, "start", true  },
  { 9.10, 1, "start", false },
  { 9.50, 1, "start", true  },
  { 9.60, 1, "start", false },
}

-- O consumo do roteiro é sequencial, então a lista tem que estar em ordem de
-- tempo (evita que um evento novo fora de lugar engula os seguintes).
table.sort(EVENTS, function(a, b) return a[1] < b[1] end)

-- ---------------------------------------------------------------------------
-- Gamepad falso (--fakepad): implementa a Gamepad API do LÖVE com um stub,
-- para exercitar o MESMO caminho de código dos controles de verdade (eixos
-- nomeados, deadzone radial, d-pad, isGamepadDown) em máquinas sem joystick
-- — o caso do WSL, onde o SDL não enxerga nenhum controle.
-- ---------------------------------------------------------------------------
local function makeFakePad()
  local st = {
    axes = { leftx = 0, lefty = 0, rightx = 0, righty = 0, triggerleft = 0, triggerright = 0 },
    buttons = {},
  }
  local j = {}
  function j:isGamepad() return true end
  function j:getGamepadAxis(a) return st.axes[a] or 0 end
  function j:isGamepadDown(...)
    for i = 1, select("#", ...) do
      if st.buttons[select(i, ...)] then return true end
    end
    return false
  end
  function j:getGUID() return "fakepad00000000000000000000000f" end
  function j:getName() return "FAKE PAD (SMOKE)" end
  function j:getID() return 99 end
  function j:getAxisCount() return 6 end
  function j:getButtonCount() return 15 end
  return { j = j, st = st }
end

-- Roteia os comandos do roteiro: device 1 vira o pad falso quando --fakepad
-- está ligado; o resto continua no device sintético.
local function press(which, action, value)
  if which == 1 and pad then
    pad.st.buttons[action == "fire" and "a" or action] = value or nil
  else
    Input.scriptPress(which, action, value)
  end
end

local function axis(which, mx, my, ax, ay)
  if which == 1 and pad then
    pad.st.axes.leftx, pad.st.axes.lefty = mx, my
    pad.st.axes.rightx, pad.st.axes.righty = ax, ay
  else
    Input.scriptAxis(which, mx, my, ax, ay)
  end
end

function Smoke.reset()
  Smoke.t = 0
  Smoke.fpsMin = 9999
  Smoke.nextEvent = 1
  Smoke.stats = {}
  Smoke.goTimer, Smoke.goPressed = 0, false
  pad = nil
  if Config.SMOKE_PAD then
    pad = makeFakePad()
    Input.addJoystick(pad.j)
    Smoke.note("pad", "fake")
  end
  Smoke.pad = pad   -- exposto para testes pontuais de input
end

function Smoke.note(key, value)
  Smoke.stats[key] = value
end

function Smoke.bump(key, amount)
  Smoke.stats[key] = (Smoke.stats[key] or 0) + (amount or 1)
end

function Smoke.max(key, value)
  if (Smoke.stats[key] or -math.huge) < value then Smoke.stats[key] = value end
end

local function finish(code)
  local s = Smoke.stats
  s.devices = Input.count
  print(string.format(
    "[smoke] t=%.1fs estado=%s devices=%d fpsMin=%d waves=%d kills=%d deaths=%d gameovers=%d pickups=%d " ..
    "combo=%d pausas=%d esperas=%d peakEnemies=%d peakBullets=%d peakParticles=%d denied=%d",
    Smoke.t, tostring(s.state or "?"), s.devices or 0, Smoke.fpsMin,
    s.waves or 0, s.kills or 0, s.deaths or 0, s.gameovers or 0, s.pickups or 0,
    s.combo or 0, s.pauses or 0, s.waits or 0, s.peakEnemies or 0, s.peakBullets or 0, s.peakParticles or 0,
    s.denied or 0))
  io.stdout:flush()
  love.event.quit(code or 0)
end

function Smoke.update(dt)
  Smoke.t = Smoke.t + dt

  -- Ignora o primeiro segundo (carga de assets/janela) na métrica de FPS.
  if Smoke.t > 1.0 then
    local fps = love.timer.getFPS()
    if fps > 0 and fps < Smoke.fpsMin then Smoke.fpsMin = fps end
  end

  while EVENTS[Smoke.nextEvent] and Smoke.t >= EVENTS[Smoke.nextEvent][1] do
    local e = EVENTS[Smoke.nextEvent]
    if e[3] == "fn" then e[4]() else press(e[2], e[3], e[4]) end
    Smoke.nextEvent = Smoke.nextEvent + 1
  end

  -- Movimento e mira em círculos de períodos diferentes: cobre todas as
  -- direções, colisão com parede e troca constante de alvo.
  local t = Smoke.t
  axis(1,
    math.cos(t * 1.7), math.sin(t * 1.3),
    math.cos(t * 0.9), math.sin(t * 1.1))
  -- O segundo bot anda em contrafase, para os dois não ficarem colados.
  axis(2,
    math.cos(t * 1.1 + 2.2), math.sin(t * 1.9 + 1.0),
    math.cos(t * 1.4 + 0.7), math.sin(t * 0.8 + 2.6))

  -- No game over, aperta START uma vez para exercitar a volta ao lobby.
  local State = require("src.state")
  if State.current() == require("src.states.gameover") then
    Smoke.goTimer = (Smoke.goTimer or 0) + dt
    if not Smoke.goPressed and Smoke.goTimer > 1.2 then
      press(1, "start", true)
      Smoke.goPressed = true
    elseif Smoke.goPressed and Smoke.goTimer > 1.4 then
      press(1, "start", false)
    end
  end

  if Smoke.t >= (Config.SMOKE_TIME or 15) then
    finish(0)
  end
end

return Smoke
