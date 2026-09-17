-- Waves, portas e telégrafo de spawn.
--
-- A cota, o intervalo e o teto de inimigos vivos saem de fórmulas em
-- src/config.lua (waveQuota / waveSpawnInterval / waveMaxAlive): a curva é
-- infinita e crescente, sem tabela de waves hardcoded.
--
-- Ciclo de uma wave:
--   escolhe porta -> pisca 0.4s (telégrafo) -> solta um lote -> repete até
--   zerar a cota -> quando a arena esvazia: bônus, vida de volta, drop
--   garantido e 3s de respiro -> próxima wave.

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")

local Spawner = {}

local DOOR_LEN = 44      -- comprimento da porta na parede
local DOOR_THICK = 6
local SPAWN_INSET = 14   -- quanto o inimigo nasce para dentro da arena

-- As 4 portas (meio de cada parede). Preenchidas em Spawner.load.
local doors = {}

-- Buffer do sorteio de tipos, reaproveitado a cada wave (não aloca em jogo).
local mixBuf = {}
for i = 1, #Config.ENEMY_MIX do mixBuf[i] = { type = "grunt", weight = 0 } end
local mixCount = 0

-- As portas ficam encostadas por dentro da parede (meia espessura de
-- distância), para não invadirem a faixa de HUD nem sair do canvas.
function Spawner.load(arena)
  local t = DOOR_THICK * 0.5
  doors[1] = { side = "top",    x = arena.cx, y = arena.y + t,
               sx = arena.cx, sy = arena.y + SPAWN_INSET }
  doors[2] = { side = "bottom", x = arena.cx, y = arena.y + arena.h - t,
               sx = arena.cx, sy = arena.y + arena.h - SPAWN_INSET }
  doors[3] = { side = "left",   x = arena.x + t, y = arena.cy,
               sx = arena.x + SPAWN_INSET, sy = arena.cy }
  doors[4] = { side = "right",  x = arena.x + arena.w - t, y = arena.cy,
               sx = arena.x + arena.w - SPAWN_INSET, sy = arena.cy }
  for i = 1, 4 do doors[i].warn = 0 end
end

-- Recalcula os pesos do mix para a wave atual.
local function buildMix(wave)
  mixCount = 0
  for i = 1, #Config.ENEMY_MIX do
    local m = Config.ENEMY_MIX[i]
    if wave >= m.from then
      local w = m.base + m.perWave * wave
      if w < m.min then w = m.min end
      if w > 0 then
        mixCount = mixCount + 1
        mixBuf[mixCount].type = m.type
        mixBuf[mixCount].weight = w
      end
    end
  end
  -- Segurança: nunca deixa o sorteio sem opção.
  if mixCount == 0 then
    mixCount = 1
    mixBuf[1].type = "grunt"
    mixBuf[1].weight = 1
  end
end

function Spawner.reset(world, startWave)
  Spawner.world = world
  Spawner.wave = (startWave or 1) - 1
  Spawner.phase = "rest"
  Spawner.timer = 1.0          -- pequeno respiro antes da primeira wave
  Spawner.quota = 0
  Spawner.spawned = 0
  Spawner.maxAlive = 0
  Spawner.interval = 1
  Spawner.door = nil
  for i = 1, 4 do doors[i].warn = 0 end
end

function Spawner.startWave(n)
  Spawner.wave = n
  Spawner.quota = Config.waveQuota(n)
  Spawner.spawned = 0
  Spawner.maxAlive = Config.waveMaxAlive(n)
  Spawner.interval = Config.waveSpawnInterval(n)
  Spawner.phase = "idle"
  Spawner.timer = 0.2
  buildMix(n)
  Audio.play("wave_start")
  if Config.SMOKE then require("src.smoke").note("waves", n) end
end

-- Recompensas ao limpar a wave: bônus, vida de volta para quem estava fora e
-- um power-up garantido no centro.
local function onWaveCleared(world)
  local bonus = Spawner.wave * Config.WAVE.clearBonus
  for i = 1, world.playerCount do
    local p = world.players[i]
    p.score = p.score + bonus
    if p.lives < Config.PLAYER.lives then
      p.lives = p.lives + 1
      -- Quem estava fora volta para a partida na próxima janela de respawn.
      if p.out then
        p.out = false
        p.respawnTimer = 0
      end
    end
  end
  world:dropPowerup(world.arena.cx, world.arena.cy, true)
  Audio.play("wave_clear")
end

local function spawnBatch(world)
  local d = Spawner.door
  if not d then return end

  local bMin, bMax = Config.waveBatch(Spawner.wave)
  local batch = Util.randInt(bMin, bMax)
  for _ = 1, batch do
    if Spawner.spawned >= Spawner.quota then break end
    if world.enemies.count >= Spawner.maxAlive then break end
    local pick = Util.weightedPick(mixBuf, mixCount)
    -- Espalha um pouco ao longo da porta para não nascerem sobrepostos.
    local jitter = Util.randRange(-DOOR_LEN * 0.4, DOOR_LEN * 0.4)
    local x = d.sx + ((d.side == "top" or d.side == "bottom") and jitter or 0)
    local y = d.sy + ((d.side == "left" or d.side == "right") and jitter or 0)
    if world:spawnEnemy(pick.type, x, y) then
      Spawner.spawned = Spawner.spawned + 1
    end
  end
  Spawner.door = nil
end

function Spawner.update(dt, world)
  for i = 1, 4 do
    if doors[i].warn > 0 then doors[i].warn = doors[i].warn - dt end
  end

  Spawner.timer = Spawner.timer - dt

  if Spawner.phase == "rest" then
    if Spawner.timer <= 0 then Spawner.startWave(Spawner.wave + 1) end
    return
  end

  -- Cota cumprida e arena limpa: fecha a wave.
  if Spawner.spawned >= Spawner.quota and world.enemies.count == 0 then
    onWaveCleared(world)
    Spawner.phase = "rest"
    Spawner.timer = Config.WAVE.restTime
    return
  end

  if Spawner.phase == "telegraph" then
    if Spawner.timer <= 0 then
      spawnBatch(world)
      Spawner.phase = "idle"
      Spawner.timer = Spawner.interval
    end
    return
  end

  -- phase == "idle": espera o intervalo e acende a próxima porta.
  if Spawner.timer <= 0
    and Spawner.spawned < Spawner.quota
    and world.enemies.count < Spawner.maxAlive then
    local d = doors[Util.randInt(1, 4)]
    d.warn = Config.WAVE.telegraphTime
    Spawner.door = d
    Spawner.phase = "telegraph"
    Spawner.timer = Config.WAVE.telegraphTime
  end
end

-- Debug (F2): mata a cota restante e limpa a arena.
function Spawner.skipWave(world)
  Spawner.spawned = Spawner.quota
  for i = world.enemies.count, 1, -1 do
    world.enemies:release(i)
  end
end

-- Quantos inimigos ainda faltam nesta wave (por spawnar + vivos).
function Spawner.remaining(world)
  return (Spawner.quota - Spawner.spawned) + world.enemies.count
end

function Spawner.isResting()
  return Spawner.phase == "rest"
end

-- ---------------------------------------------------------------------------
-- Desenho das portas (e do telégrafo piscando).
-- ---------------------------------------------------------------------------
function Spawner.draw()
  local C = Config.COLORS
  for i = 1, 4 do
    local d = doors[i]
    local horizontal = (d.side == "top" or d.side == "bottom")
    local w = horizontal and DOOR_LEN or DOOR_THICK
    local h = horizontal and DOOR_THICK or DOOR_LEN

    if d.warn > 0 then
      -- Pisca em vermelho e "respira" um pouco para chamar atenção.
      local on = math.floor(d.warn * 16) % 2 == 0
      love.graphics.setColor(on and C.doorWarn or C.door)
      local grow = on and 2 or 0
      love.graphics.rectangle("fill",
        d.x - w * 0.5 - (horizontal and grow or 0),
        d.y - h * 0.5 - (horizontal and 0 or grow),
        w + (horizontal and grow * 2 or 0),
        h + (horizontal and 0 or grow * 2))
    else
      love.graphics.setColor(C.door)
      love.graphics.rectangle("fill", d.x - w * 0.5, d.y - h * 0.5, w, h)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

Spawner.doors = doors
return Spawner
