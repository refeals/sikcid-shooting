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

-- Timeline: {tempo, ação, valor} para botões, ou {tempo, "fn", função}.
-- Um pulso de botão = press + release.
local EVENTS = {
  { 0.40, "start", true  },   -- vincula o Jogador 1
  { 0.50, "start", false },
  { 1.20, "start", true  },   -- inicia a partida (debounce já passou)
  { 1.30, "start", false },
  -- Abre e fecha a tela de teste de input (F5), exercitando push/pop da pilha.
  { 1.60, "fn", function() love.keypressed("f5", "f5", false) end },
  { 1.80, "fn", function() love.keypressed("f5", "f5", false) end },
}

function Smoke.reset()
  Smoke.t = 0
  Smoke.fpsMin = 9999
  Smoke.nextEvent = 1
  Smoke.stats = {}
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
  print(string.format(
    "[smoke] t=%.1fs estado=%s fpsMin=%d waves=%d kills=%d deaths=%d pickups=%d " ..
    "peakEnemies=%d peakBullets=%d peakParticles=%d denied=%d",
    Smoke.t, tostring(s.state or "?"), Smoke.fpsMin,
    s.waves or 0, s.kills or 0, s.deaths or 0, s.pickups or 0,
    s.peakEnemies or 0, s.peakBullets or 0, s.peakParticles or 0, s.denied or 0))
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
    if e[2] == "fn" then e[3]() else Input.scriptPress(e[2], e[3]) end
    Smoke.nextEvent = Smoke.nextEvent + 1
  end

  -- Movimento e mira em círculos de períodos diferentes: cobre todas as
  -- direções, colisão com parede e troca constante de alvo.
  local t = Smoke.t
  Input.scriptAxis(
    math.cos(t * 1.7), math.sin(t * 1.3),
    math.cos(t * 0.9), math.sin(t * 1.1))

  if Smoke.t >= (Config.SMOKE_TIME or 15) then
    finish(0)
  end
end

return Smoke
