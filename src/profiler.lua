-- Medidor de frame para hardware antigo (só com Config.DEBUG).
--
-- Mede o TRABALHO do frame — do início do update ao fim do draw —, não o dt:
-- com vsync ligado o dt fica em ~16.6ms mesmo com o jogo folgado, porque
-- inclui a espera pela tela. Se o trabalho passar de Config.PROFILE_WARN_MS,
-- imprime qual dos sistemas medidos pesou mais.
--
-- Nenhuma alocação por frame: as seções são campos fixos e o texto só é
-- montado quando o aviso de fato sai (no máximo um por PROFILE_WARN_INTERVAL).

local Config = require("src.config")

local getTime = love.timer.getTime

-- Os primeiros frames pagam custos únicos (cache de glifos da fonte, primeiro
-- uso do canvas) que não dizem nada sobre o jogo: não entram no aviso.
local WARMUP_FRAMES = 30

local Profiler = {
  frameStart = 0,
  frames = 0,
  lastWarn = -math.huge,
  -- Tempo acumulado no frame atual, por sistema (segundos).
  enemies = 0,     -- update dos inimigos
  collision = 0,   -- grid + colisões + separação
  particles = 0,   -- update e desenho das partículas
  post = 0,        -- pós-processamento: glow + composição da cena (src/post.lua)
  -- Início da medição em andamento, por sistema.
  startAt = { enemies = 0, collision = 0, particles = 0, post = 0 },
  -- Contagem de entidades, preenchida pelo game (entra no aviso).
  counts = { enemies = 0, bullets = 0, particles = 0 },
}

local LABELS = {
  enemies = "update de inimigos",
  collision = "colisao",
  particles = "particulas",
  post = "pos-processamento",
}

function Profiler.beginFrame()
  if not Config.DEBUG then return end
  Profiler.frameStart = getTime()
  Profiler.enemies, Profiler.collision, Profiler.particles, Profiler.post = 0, 0, 0, 0
end

-- Uso: Profiler.start("enemies") ... Profiler.stop("enemies")
function Profiler.start(name)
  if not Config.DEBUG then return end
  Profiler.startAt[name] = getTime()
end

function Profiler.stop(name)
  if not Config.DEBUG then return end
  Profiler[name] = Profiler[name] + (getTime() - Profiler.startAt[name])
end

function Profiler.setCounts(enemies, bullets, particles)
  local c = Profiler.counts
  c.enemies, c.bullets, c.particles = enemies, bullets, particles
end

function Profiler.endFrame()
  if not Config.DEBUG then return end
  if Profiler.frames < WARMUP_FRAMES then
    Profiler.frames = Profiler.frames + 1
    return
  end
  local now = getTime()
  local total = (now - Profiler.frameStart) * 1000
  if total <= Config.PROFILE_WARN_MS then return end
  if now - Profiler.lastWarn < Config.PROFILE_WARN_INTERVAL then return end
  Profiler.lastWarn = now

  local e = Profiler.enemies * 1000
  local c = Profiler.collision * 1000
  local p = Profiler.particles * 1000
  local fx = Profiler.post * 1000
  local rest = total - e - c - p - fx

  local worst, worstMs = "enemies", e
  if c > worstMs then worst, worstMs = "collision", c end
  if p > worstMs then worst, worstMs = "particles", p end
  if fx > worstMs then worst, worstMs = "post", fx end

  -- Se o resto (HUD, jogadores, balas, desenho geral) domina, diz isso em vez
  -- de culpar um sistema que não é o gargalo.
  local culprit = LABELS[worst]
  if rest > worstMs then culprit = "fora dos sistemas medidos (desenho/HUD/balas)" end

  local n = Profiler.counts
  print(string.format(
    "[perf] frame %.1fms > %gms | mais pesado: %s | inimigos %.2fms  colisao %.2fms  particulas %.2fms  post %.2fms  resto %.2fms | in %d bal %d par %d",
    total, Config.PROFILE_WARN_MS, culprit, e, c, p, fx, rest,
    n.enemies, n.bullets, n.particles))
  io.stdout:flush()
end

return Profiler
