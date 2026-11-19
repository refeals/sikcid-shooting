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
--
-- Boss waves (every Config.BOSS.every): the boss (world.boss) runs the show
-- and the wave closes when it is done. From boss `adds.fromBoss` on, the
-- doors keep feeding normal enemies (no quota) while it fights.

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")
local Assets = require("src.assets")

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
  -- Drawing anchors: the hatch sprite sits centered on the wall line (half of
  -- it is outside the arena, covered by the HUD or the screen edge) and
  -- `inward` is the direction pointing into the arena.
  local wall = {
    top    = { arena.cx, arena.y, math.pi / 2 },
    bottom = { arena.cx, arena.y + arena.h, -math.pi / 2 },
    left   = { arena.x, arena.cy, 0 },
    right  = { arena.x + arena.w, arena.cy, math.pi },
  }
  for i = 1, 4 do
    local d = doors[i]
    local w = wall[d.side]
    d.warn = 0
    d.wx, d.wy, d.inward = w[1], w[2], w[3]
  end
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
  Spawner.banner = 0
  Spawner.bossWave = false
  for i = 1, 4 do doors[i].warn = 0 end
end

function Spawner.isBossWave(n)
  return n >= 1 and n % Config.BOSS.every == 0
end

function Spawner.startWave(n)
  Spawner.wave = n
  Spawner.spawned = 0
  Spawner.phase = "idle"
  Spawner.timer = 0.2
  buildMix(n)
  if Config.SMOKE then require("src.smoke").note("waves", n) end

  Spawner.bossWave = Spawner.isBossWave(n)
  if Spawner.bossWave then
    local bossN = n / Config.BOSS.every
    local A = Config.BOSS.adds
    -- No quota: adds keep coming until the boss dies (or none at all for the
    -- first bosses). The ALERTA banner replaces the "WAVE N" one.
    Spawner.quota = bossN >= A.fromBoss and math.huge or 0
    Spawner.maxAlive = math.min(Config.MAX_ENEMIES, math.floor(Config.bossValue(A.maxAlive, bossN)))
    Spawner.interval = Config.bossValue(A.interval, bossN)
    Spawner.banner = 0
    Spawner.world.boss:begin(Spawner.world, bossN, n)
    return
  end

  Spawner.quota = Config.waveQuota(n)
  Spawner.maxAlive = Config.waveMaxAlive(n)
  Spawner.interval = Config.waveSpawnInterval(n)
  Spawner.banner = Config.WAVE.bannerTime
  Audio.play("wave_start")
end

-- Recompensas ao limpar a wave: bônus, vida de volta para quem estava fora e
-- um power-up garantido num ponto vazio.
local function onWaveCleared(world)
  local bonus = Spawner.wave * Config.WAVE.clearBonus
  for i = 1, world.playerCount do
    local p = world.players[i]
    p.score = p.score + bonus
    if p.lives < Config.PLAYER.lives then
      p.lives = p.lives + 1
      -- Quem estava fora volta para a partida na próxima janela de respawn,
      -- no ponto seguro e SEM o suporte de respawn (não é uma morte).
      if p.out then
        p.out = false
        p.respawnTimer = 0
        p.revived = true
        p:placeMarker(world)
      end
    end
  end
  -- After the revivals: the drop avoids where they are about to appear.
  local x, y = world:dropSpot()
  world:dropPowerup(x, y, true)
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
    local e = world:spawnEnemy(pick.type, x, y)
    if e then
      Spawner.spawned = Spawner.spawned + 1
      -- "Pop" de partículas na porta: o inimigo não aparece do nada.
      world:burst(4, x, y, e.color, 3)
    end
  end
  Spawner.door = nil
end

function Spawner.update(dt, world)
  for i = 1, 4 do
    if doors[i].warn > 0 then doors[i].warn = doors[i].warn - dt end
  end
  if Spawner.banner > 0 then Spawner.banner = Spawner.banner - dt end

  Spawner.timer = Spawner.timer - dt

  if Spawner.phase == "rest" then
    if Spawner.timer <= 0 then Spawner.startWave(Spawner.wave + 1) end
    return
  end

  if Spawner.bossWave then
    -- The boss closes the wave; the doors only work while it fights.
    local boss = world.boss
    if boss.state == "done" then
      boss:clear()
      Spawner.bossWave = false
      onWaveCleared(world)
      Spawner.phase = "rest"
      Spawner.timer = Config.WAVE.restTime
      return
    end
    if not boss:isFighting() then
      Spawner.door = nil
      Spawner.phase = "idle"
      return
    end
  elseif Spawner.spawned >= Spawner.quota and world.enemies.count == 0 then
    -- Cota cumprida e arena limpa: fecha a wave.
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
    Audio.play("door_warn")
    Spawner.door = d
    Spawner.phase = "telegraph"
    Spawner.timer = Config.WAVE.telegraphTime
  end
end

-- Debug (F2): mata a cota restante e limpa a arena. Numa wave de boss,
-- dispara a morte do boss (que limpa o resto).
function Spawner.skipWave(world)
  if Spawner.bossWave and world.boss.active then
    Spawner.spawned = Spawner.quota
    world.boss:startDeath(world)
    return
  end
  Spawner.spawned = Spawner.quota
  for i = world.enemies.count, 1, -1 do
    world.enemies:release(i)
  end
end

-- Quantos inimigos ainda faltam nesta wave (por spawnar + vivos).
function Spawner.remaining(world)
  if Spawner.bossWave then return world.enemies.count end
  return (Spawner.quota - Spawner.spawned) + world.enemies.count
end

function Spawner.isResting()
  return Spawner.phase == "rest"
end

-- ---------------------------------------------------------------------------
-- Door drawing: a Kenney hatch set into each wall, with a red light that
-- flashes during the spawn telegraph (same timing as before).
-- ---------------------------------------------------------------------------
function Spawner.draw()
  local C = Config.COLORS
  local D = Config.ART.door
  local g = love.graphics
  for i = 1, 4 do
    local d = doors[i]
    local ix, iy = math.cos(d.inward), math.sin(d.inward)

    -- Hatch body. Its long side runs along the wall; it is squashed so only
    -- D.thick px poke into the arena.
    local spr = Assets.sprite("door")
    local depth = DOOR_LEN * spr.h / spr.w     -- full sprite depth at this length
    g.setColor(1, 1, 1, 1)
    Assets.draw("door", d.wx, d.wy, d.inward, DOOR_LEN, 1, (D.thick * 2) / depth)

    local on = d.warn > 0 and math.floor(d.warn * 16) % 2 == 0
    local lx, ly = d.wx + ix * (D.thick - 5), d.wy + iy * (D.thick - 5)
    if on then
      -- Glow, then the lit lamp.
      g.setBlendMode("add")
      g.setColor(C.doorWarn[1], C.doorWarn[2], C.doorWarn[3], 0.55)
      g.circle("fill", lx, ly, D.light * 1.6)
      g.setBlendMode("alpha")
      g.setColor(1, 1, 1, 1)
    else
      g.setColor(0.45, 0.45, 0.5, 1)
    end
    Assets.draw("doorLight", lx, ly, 0, D.light)
  end
  g.setColor(1, 1, 1, 1)
end

Spawner.doors = doors
return Spawner
