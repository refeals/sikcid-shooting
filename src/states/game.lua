-- Tela 2: arena.
--
-- ETAPA 4: inimigos, colisão, morte, partículas, vidas/respawn/invulnerabilidade.
-- O spawn ainda é provisório (ver TEMP_SPAWN) e vira o sistema de waves na
-- etapa 5; combo, power-ups e game over entram nas etapas 6/7/8.

local Config   = require("src.config")
local Util     = require("src.util")
local State    = require("src.state")
local Screen   = require("src.screen")
local Pool     = require("src.pool")
local Hud      = require("src.hud")
local Audio    = require("src.audio")
local Save     = require("src.save")
local Combat   = require("src.systems.combat")
local Spawner  = require("src.systems.spawner")
local Combo    = require("src.systems.combo")
local Powerups = require("src.systems.powerups")
local Pickup   = require("src.entities.pickup")
local Player   = require("src.entities.player")
local Bullet   = require("src.entities.bullet")
local Enemy    = require("src.entities.enemy")
local Boss     = require("src.entities.boss")
local Particle = require("src.entities.particle")
local Profiler = require("src.profiler")
local Shaders  = require("src.shaders")
local Background = require("src.background")
local UI        = require("src.ui")

local Game = {}

local J = Config.JUICE

-- Arena = tela inteira menos a faixa de HUD no topo.
local arena = {
  x = 0,
  y = Config.HUD_H,
  w = Config.VIRTUAL_W,
  h = Config.VIRTUAL_H - Config.HUD_H,
}
arena.cx = arena.x + arena.w * 0.5
arena.cy = arena.y + arena.h * 0.5

-- Pools criados uma única vez no carregamento do módulo; entre partidas são
-- apenas limpos (nenhuma tabela é realocada durante o jogo).
local bullets   = Pool.new(Bullet.new, Config.MAX_BULLETS)
local enemies   = Pool.new(Enemy.new, Config.MAX_ENEMIES)
local particles = Pool.new(Particle.new, Config.MAX_PARTICLES)
local pickups   = Pool.new(Pickup.new, Config.MAX_PICKUPS)

local world = {
  arena = arena,
  bullets = bullets,
  enemies = enemies,
  particles = particles,
  pickups = pickups,
  boss = Boss.new(),   -- one instance, reused every boss wave
  players = {},
  playerCount = 0,
  godMode = false,
}

-- ---------------------------------------------------------------------------
-- Serviços que as entidades e os sistemas consomem
-- ---------------------------------------------------------------------------
function world:spawnBullet(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  local b = self.bullets:acquire()
  if not b then return nil end
  b:reset(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  return b
end

function world:spawnEnemy(kind, x, y)
  local e = self.enemies:acquire()
  if not e then return nil end
  e:reset(kind, x, y)
  return e
end

function world:nearestPlayer(x, y)
  local best, bestD2 = nil, math.huge
  for i = 1, self.playerCount do
    local p = self.players[i]
    if p.alive then
      local d2 = Util.dist2(x, y, p.x, p.y)
      if d2 < bestD2 then best, bestD2 = p, d2 end
    end
  end
  return best
end

-- Inimigo mais próximo dentro de `maxR` (usa o grid da broadphase, então é
-- barato mesmo com um punhado de mísseis voando).
function world:nearestEnemy(x, y, maxR)
  local best, bestD2 = nil, maxR * maxR
  Combat.queryCircle(x, y, maxR, function(e)
    if e.dead then return end
    local d2 = Util.dist2(x, y, e.x, e.y)
    if d2 < bestD2 then best, bestD2 = e, d2 end
  end)
  -- The boss lives outside the grid.
  local boss = self.boss
  if not boss.dead then
    local d2 = Util.dist2(x, y, boss.x, boss.y)
    if d2 < bestD2 then best = boss end
  end
  return best
end

-- Whether a point is inside the visible playfield. With no camera the screen
-- shows the whole arena; a scrolling arena would test the camera view here.
function world:isOnScreen(x, y)
  local a = self.arena
  return x >= a.x and x <= a.x + a.w and y >= a.y and y <= a.y + a.h
end

-- Nearest live enemy whose center is on screen (auto-aim). A plain scan: the
-- pool caps it at MAX_ENEMIES and it runs once per player per frame.
function world:nearestVisibleEnemy(x, y)
  local pool = self.enemies
  local best, bestD2 = nil, math.huge
  for i = 1, pool.count do
    local e = pool.items[i]
    if not e.dead and self:isOnScreen(e.x, e.y) then
      local d2 = Util.dist2(x, y, e.x, e.y)
      if d2 < bestD2 then best, bestD2 = e, d2 end
    end
  end
  local boss = self.boss
  if not boss.dead and self:isOnScreen(boss.x, boss.y) then
    if Util.dist2(x, y, boss.x, boss.y) < bestD2 then best = boss end
  end
  return best
end

function world:randomPlayer()
  local alive, n = nil, 0
  for i = 1, self.playerCount do
    local p = self.players[i]
    if p.alive then
      n = n + 1
      if math.random(n) == 1 then alive = p end   -- reservoir sampling
    end
  end
  return alive
end

-- Respawna se o parceiro estiver vivo (ou se ele já estiver fora de vez, caso
-- em que a partida segue com um jogador só).
function world:canRespawn(player)
  if self.playerCount == 1 then return true end
  local other = self.players[player.index == 1 and 2 or 1]
  if not other or other.alive or other.out then return true end
  -- Parceiro também caído: espera ele voltar, mas no máximo 0.5s a mais,
  -- senão os dois ficariam presos esperando um pelo outro.
  return player.respawnTimer <= -0.5
end

function world:addScore(playerIndex, points)
  local p = self.players[playerIndex]
  if p then p.score = p.score + points end
end

-- Atalho para efeitos soltarem partículas sem conhecer o pool.
function world:burst(count, x, y, color, size)
  Particle.burst(self.particles, count, x, y, color, size)
end

function world:explosion(x, y, color, puffs, puffSize, sparks, sparkSize)
  Particle.explosion(self.particles, x, y, color, puffs, puffSize, sparks, sparkSize)
end

-- ---------------------------------------------------------------------------
-- Effect rings (NOVA shockwave, bubble pop, salvo blasts): fixed slots, the
-- oldest is overwritten; nothing is allocated during play.
-- ---------------------------------------------------------------------------
local RING_SLOTS = 10
local rings = {}
for i = 1, RING_SLOTS do rings[i] = { x = 0, y = 0, r = 0, t = 0, life = 0, color = nil } end

function world:ring(x, y, radius, color, life)
  local slot, oldest = 1, math.huge
  for i = 1, RING_SLOTS do
    local left = rings[i].life - rings[i].t
    if left < oldest then slot, oldest = i, left end
  end
  local g = rings[slot]
  g.x, g.y, g.r, g.t, g.life, g.color = x, y, radius, 0, life or 0.35, color
end

local function updateRings(dt)
  for i = 1, RING_SLOTS do
    local g = rings[i]
    if g.t < g.life then g.t = g.t + dt end
  end
end

local function drawRings()
  local gr = love.graphics
  gr.setBlendMode("add")
  for i = 1, RING_SLOTS do
    local g = rings[i]
    if g.t < g.life then
      local k = g.t / g.life
      local c = g.color
      gr.setColor(c[1], c[2], c[3], (1 - k) * 0.9)
      gr.setLineWidth(3 * (1 - k) + 1)
      gr.circle("line", g.x, g.y, g.r * (0.25 + 0.75 * k))
    end
  end
  gr.setLineWidth(1)
  gr.setBlendMode("alpha")
end

-- ---------------------------------------------------------------------------
-- Spots: random candidates inside the arena, scored, best one wins.
-- ---------------------------------------------------------------------------
local RS = Config.RESPAWN

-- Distance from (x, y) to the nearest threat: enemy (minus its size), the
-- boss hull, enemy shots. math.huge with none around.
local function threatDistance(self, x, y)
  local best = math.huge
  local pool = self.enemies
  for i = 1, pool.count do
    local e = pool.items[i]
    if not e.dead then
      local d = math.sqrt(Util.dist2(x, y, e.x, e.y)) - e.space
      if d < best then best = d end
    end
  end
  local boss = self.boss
  if boss.active and boss.state ~= "done" then
    local d = math.sqrt(Util.dist2(x, y, boss.x, boss.y)) - boss.size * 0.5
    if d < best then best = d end
  end
  local shots = self.bullets
  for i = 1, shots.count do
    local b = shots.items[i]
    if b.owner == "enemy" and not b.dead then
      local d = math.sqrt(Util.dist2(x, y, b.x, b.y))
      if d < best then best = d end
    end
  end
  return best
end

-- Safest spot to respawn: farthest from every threat. The arena center is
-- candidate zero, so with nothing around (wave end) it wins the tie.
function world:safeSpot()
  local a, m = self.arena, RS.margin
  local bx, by = a.cx, a.cy
  local bestScore = threatDistance(self, bx, by)
  for _ = 1, RS.samples do
    local x = Util.randRange(a.x + m, a.x + a.w - m)
    local y = Util.randRange(a.y + m, a.y + a.h - m)
    local s = threatDistance(self, x, y)
    if s > bestScore then bx, by, bestScore = x, y, s end
  end
  return bx, by
end

-- Wave-end drop: the spot farthest from the live players and from where the
-- dead ones will come back (their markers), so nobody grabs it unseen.
function world:dropSpot()
  local a, m = self.arena, Config.POWERUP.dropMargin
  local bx, by, bestScore = a.cx, a.cy, -1
  for _ = 1, Config.POWERUP.dropSamples do
    local x = Util.randRange(a.x + m, a.x + a.w - m)
    local y = Util.randRange(a.y + m, a.y + a.h - m)
    local s = math.huge
    for i = 1, self.playerCount do
      local p = self.players[i]
      local px, py
      if p.alive then px, py = p.x, p.y
      elseif not p.out then px, py = p.markerX, p.markerY end
      if px then
        local d = Util.dist2(x, y, px, py)
        if d < s then s = d end
      end
    end
    if s > bestScore then bx, by, bestScore = x, y, s end
  end
  return bx, by
end

-- ---------------------------------------------------------------------------
-- Area damage (NOVA, salvo blasts): enemies through the grid, the boss
-- directly. Kills are flagged dead and swept by Combat at the end of the
-- frame. The query callback is module-level, fed by upvalues.
-- ---------------------------------------------------------------------------
local adX, adY, adR, adDmg, adOwner = 0, 0, 0, 0, nil

local function areaHit(e)
  if e.dead then return end
  local rr = adR + e.radius
  if Util.dist2(adX, adY, e.x, e.y) > rr * rr then return end
  if e:damage(adDmg) then
    e.dead = true
    world:onEnemyKilled(e, adOwner)
  end
end

function world:areaDamage(x, y, radius, dmg, owner)
  adX, adY, adR, adDmg, adOwner = x, y, radius, dmg, owner
  Combat.queryCircle(x, y, radius + Config.ENEMY_SPACING.maxSpace, areaHit)
  local boss = self.boss
  if boss:isFighting() then
    local rr = radius + boss.radius
    if Util.dist2(x, y, boss.x, boss.y) <= rr * rr then boss:hit(dmg, owner, self) end
  end
end

-- Erases enemy shots (and boss missiles) within `radius`.
function world:clearEnemyShots(x, y, radius)
  local shots, r2 = self.bullets, radius * radius
  for i = 1, shots.count do
    local b = shots.items[i]
    if b.owner == "enemy" and not b.dead and Util.dist2(x, y, b.x, b.y) <= r2 then
      b.dead = true
      Particle.burst(self.particles, 2, b.x, b.y, b.color, 3)
    end
  end
end

-- NOVA power-up: shockwave around the player.
function world:nova(p)
  local NV = Config.POWERUPS.nova
  self:areaDamage(p.x, p.y, NV.radius, NV.damage, p.index)
  self:clearEnemyShots(p.x, p.y, NV.radius)
  self:ring(p.x, p.y, NV.radius, p.color, 0.45)
  self:ring(p.x, p.y, NV.radius * 0.7, Config.COLORS.flash, 0.35)
  Particle.burst(self.particles, 14, p.x, p.y, p.color, 5)
  Background.pulse(p.x, p.y, 0.8)
  self:shake(4)
end

-- A respawn salvo missile going off: its own hit already dealt `dmg`; the
-- blast hurts everything around.
function world:salvoBlast(b)
  local S = RS.salvo
  self:areaDamage(b.x, b.y, S.blastRadius, S.blastDamage, b.owner)
  Particle.explosion(self.particles, b.x, b.y, b.color, 3, S.blastRadius * 0.6, 6, 4)
  self:ring(b.x, b.y, S.blastRadius, b.color, 0.3)
  self:shake(1.5)
  Audio.play("salvo_blast")
end

-- Respawn support (back with lives left): a salvo of homing missiles, each
-- to a different nearby enemy (the boss counts), fired out in a ring, plus a
-- weapon power-up dropped close by.
local salvoTargets = {}

function world:respawnSupport(p)
  local S = RS.salvo
  local count = math.min(S.max, S.base + math.floor(Spawner.wave / S.everyWaves))

  -- The `count` nearest distinct targets (small n: repeated nearest search).
  local n = 0
  for _ = 1, count do
    local best, bestD2 = nil, math.huge
    local pool = self.enemies
    for i = 1, pool.count do
      local e = pool.items[i]
      if not e.dead then
        local taken = false
        for k = 1, n do if salvoTargets[k] == e then taken = true; break end end
        if not taken then
          local d2 = Util.dist2(p.x, p.y, e.x, e.y)
          if d2 < bestD2 then best, bestD2 = e, d2 end
        end
      end
    end
    local boss = self.boss
    if not boss.dead then
      local taken = false
      for k = 1, n do if salvoTargets[k] == boss then taken = true; break end end
      if not taken and Util.dist2(p.x, p.y, boss.x, boss.y) < bestD2 then best = boss end
    end
    if not best then break end
    n = n + 1
    salvoTargets[n] = best
  end

  for i = 1, count do
    local ang = (i - 1) / count * math.pi * 2 - math.pi / 2
    local b = self:spawnBullet(p.x, p.y, math.cos(ang), math.sin(ang), S.speed, S.damage,
      p.index, "salvo", S.life, 4, p.color)
    if b then b.target = salvoTargets[i] end
  end
  for k = 1, n do salvoTargets[k] = nil end
  Audio.play("salvo_launch")
  self:ring(p.x, p.y, 40, p.color, 0.3)

  -- Weapon drop close by, kept inside the arena.
  local a, m = self.arena, Config.POWERUP.dropMargin
  local ang = math.random() * math.pi * 2
  local dist = Util.randRange(RS.dropDistMin, RS.dropDistMax)
  local x = Util.clamp(p.x + math.cos(ang) * dist, a.x + m, a.x + a.w - m)
  local y = Util.clamp(p.y + math.sin(ang) * dist, a.y + m, a.y + a.h - m)
  self:dropPowerup(x, y, true, Powerups.pickWeapon())
end

-- BOLHA: absorbs the hit, pops (pushes the enemies around away), and grants
-- a short invulnerability.
local popX, popY, popR, popPush = 0, 0, 0, 0

local function popPushOne(e)
  if e.dead then return end
  local dx, dy = e.x - popX, e.y - popY
  local d2 = dx * dx + dy * dy
  local rr = popR + e.space
  if d2 >= rr * rr or d2 <= 0.0001 then return end
  local d = math.sqrt(d2)
  e:push(dx / d * popPush, dy / d * popPush)
end

local function popBubble(self, p)
  local BB = Config.POWERUPS.bubble
  Powerups.consume(p, "bubble")
  p.invuln = math.max(p.invuln, BB.invuln)
  popX, popY, popR, popPush = p.x, p.y, BB.pushRadius, BB.push
  Combat.queryCircle(p.x, p.y, BB.pushRadius + Config.ENEMY_SPACING.maxSpace, popPushOne)
  self:ring(p.x, p.y, BB.pushRadius, { 0.60, 0.95, 1.00 }, 0.35)
  Particle.burst(self.particles, 10, p.x, p.y, { 0.60, 0.95, 1.00, 1 }, 4)
  Audio.play("bubble_pop")
end

-- The boss died: every enemy blows up (no points) and every enemy shot pops.
-- Enemies leave the pool right away (flagged dead first, so collision
-- queries this frame skip them); bullets are flagged and swept by Combat, so
-- this is safe to call from inside the collision loops.
function world:clearHostiles()
  local pool = self.enemies
  for i = pool.count, 1, -1 do
    local e = pool.items[i]
    local size = Config.ART.size[e.type] or e.def.size
    Particle.explosion(self.particles, e.x, e.y, e.color, J.deathPuffs, size * 0.7,
      J.deathParticles, e.def.size * 0.35)
    e.dead = true
    pool:release(i)
  end
  local shots = self.bullets
  for i = 1, shots.count do
    local b = shots.items[i]
    if b.owner == "enemy" and not b.dead then
      b.dead = true
      Particle.burst(self.particles, 2, b.x, b.y, b.color, 3)
    end
  end
end

-- Missile smoke: skipped while the pool is busy, so explosions keep priority.
function world:trail(x, y, color)
  local pool = self.particles
  if pool.count >= Config.MAX_PARTICLES * J.trailPoolShare then return end
  Particle.trail(pool, x, y, color)
end

-- `force` (player death, boss finale) skips the fatigue: those must land.
function world:shake(mag, force)
  if not force then
    local F = J.shakeFatigue
    local fatigue = self.shakeFatigue
    self.shakeFatigue = math.min(1, fatigue + mag * F.gain)
    mag = mag * math.max(F.minMul, 1 - fatigue)
  end
  mag = mag * J.shakeScale
  if mag > self.shakeMag then self.shakeMag = mag end
end

-- Tank hit-stops share a cooldown (a chain of kills would stutter);
-- `force` (boss finale) always freezes.
function world:hitStop(t, force)
  if not force then
    if self.hitStopCooldown > 0 then return end
    self.hitStopCooldown = J.hitStopCooldown
  end
  if t > self.hitStopTimer then self.hitStopTimer = t end
end

function world:onEnemyKilled(enemy, killerIndex)
  local tank = enemy.type == "tank"
  local size = Config.ART.size[enemy.type] or enemy.def.size
  Particle.explosion(self.particles, enemy.x, enemy.y, enemy.color,
    tank and J.tankDeathPuffs or J.deathPuffs, size * 0.7,
    tank and J.tankDeathParticles or J.deathParticles, enemy.def.size * 0.35)

  -- Combo sobe primeiro: a morte já conta com o multiplicador novo.
  if type(killerIndex) == "number" then
    local killer = self.players[killerIndex]
    if killer then
      Combo.add(killer)
      self:addScore(killerIndex, enemy.def.points * Combo.mult(killer))
    end
  end

  self:dropPowerup(enemy.x, enemy.y, false)

  if enemy.type == "tank" then
    self:shake(J.shakeTankDeath)
    Background.pulse(enemy.x, enemy.y, Config.ART.background.grid.tankDeath)
    self:hitStop(J.hitStopTank)
    Audio.play("tank_die")
  else
    self:shake(J.shakeEnemyDeath)
    Audio.play("enemy_die")
  end

  if Config.SMOKE then require("src.smoke").bump("kills") end
end

function world:onPlayerHit(player)
  -- One hit per moment: the bubble's invulnerability also covers the other
  -- collision checks of the same frame.
  if not player.alive or player.invuln > 0 then return end
  if player.mods.bubble then
    popBubble(self, player)
    return
  end
  player.alive = false
  player.lives = player.lives - 1
  Combo.breakOn(player)
  Particle.explosion(self.particles, player.x, player.y, player.color,
    J.playerDeathPuffs, Config.ART.size.playerShip, J.playerDeathParticles, 5)
  self:shake(J.shakePlayerDeath, true)
  Audio.play("player_die")

  if player.lives <= 0 then
    player.lives = 0
    player.out = true
  else
    player.respawnTimer = Config.PLAYER.respawnTime
    player.revived = false
    player:markDeath()
  end

  if Config.SMOKE then require("src.smoke").bump("deaths") end
end

-- Resumo da partida, reaproveitado (nenhuma tabela nova no fim do jogo).
local summary = {
  playerCount = 0,
  scores = {}, combos = {}, devices = {},
  wave = 1, wavesCleared = 0,
  beat = { solo = false, duo = false, coop = false },
}

function world:onGameOver()
  summary.playerCount = self.playerCount
  for i = 1, self.playerCount do
    local p = self.players[i]
    summary.scores[i] = p.score
    summary.combos[i] = p.comboBest
    summary.devices[i] = p.device
  end
  summary.wave = Spawner.wave
  -- A wave em andamento não conta como sobrevivida.
  summary.wavesCleared = math.max(0, Spawner.wave - 1)

  local beat = Save.submitMatch(self.playerCount, summary.scores)
  summary.beat.solo, summary.beat.duo, summary.beat.coop = beat.solo, beat.duo, beat.coop

  -- Shake is only updated by the arena: clear it or the next screen inherits
  -- the last frame's offset.
  Screen.setShake(0, 0)
  State.switch(require("src.states.gameover"), summary)
end

-- Solta um power-up. `guaranteed` = drop de fim de wave (sempre sai); senão
-- passa pelo sorteio de Config.POWERUP.dropChance. `def` força qual (o drop
-- de arma do respawn); sem ele, sorteia.
function world:dropPowerup(x, y, guaranteed, def)
  if not guaranteed and math.random() > Config.POWERUP.dropChance then return end
  def = def or Powerups.pick()
  if not def then return end
  local p = self.pickups:acquire()
  if not p then return end
  p:reset(x, y, def)
  return p
end

-- ---------------------------------------------------------------------------
local showHitboxes = false
-- Last wave / rest phase the sky reacted to, and the parallax focus (kept
-- while every player is dead, so the sky doesn't snap back to the center).
local bgWave, bgResting = 0, true
local bgFocusX, bgFocusY = arena.cx, arena.cy
-- HUD center text, reused every frame: a label plus its number (the number is
-- drawn in the digits font, see UI.textNumber).
local hudInfo = { titleLabel = "WAVE ", titleNum = "", subLabel = "", subNum = "" }

-- Number strings drawn every frame, re-formatted only when the value changes
-- (no new string per frame). One slot per on-screen number.
local numCache = {
  wave = { v = nil, s = "" }, enemies = { v = nil, s = "" },
  rest = { v = nil, s = "" }, bonus = { v = nil, s = "" },
}
local function numStr(slot, value, fmt)
  local c = numCache[slot]
  if c.v ~= value then
    c.v = value
    c.s = string.format(fmt, value)
  end
  return c.s
end

function Game:enter(devices, count)
  world.playerCount = count or 1
  world.players = {}
  world.shakeMag = 0
  world.shakeFatigue = 0
  world.hitStopTimer = 0
  world.hitStopCooldown = 0
  world.godMode = Config.SMOKE_GOD or false
  bullets:clear()
  enemies:clear()
  particles:clear()
  pickups:clear()
  world.boss:clear()
  Spawner.load(arena)
  Spawner.reset(world, Config.SMOKE_WAVE)
  -- Sky set straight to the starting wave's palette (--wave 25 starts there).
  Background.reset(Background.themeForWave(Spawner.wave + 1))
  bgWave, bgResting = Spawner.wave, true
  bgFocusX, bgFocusY = arena.cx, arena.cy

  for i = 1, world.playerCount do
    local p = Player.new(i, devices[i])
    local dx = world.playerCount == 1 and 0 or (i == 1 and -30 or 30)
    p:spawn(arena.cx + dx, arena.cy)
    Combo.reset(p)
    world.players[i] = p
  end

  -- A arena já está montada; o briefing fica por cima (tudo congelado) até
  -- alguém apertar START.
  State.push(require("src.states.briefing"), world)
end

-- Sky reactions: palette per block of waves, grid ripples on wave start and
-- clear, parallax following the players' center.
local function updateBackground(dt)
  local BG = Config.ART.background
  if Spawner.wave ~= bgWave then
    bgWave = Spawner.wave
    Background.setTheme(Background.themeForWave(bgWave))
    Background.pulse(arena.cx, arena.cy, BG.grid.waveStart)
  end
  local resting = Spawner.isResting()
  if resting and not bgResting and Spawner.wave >= 1 then
    Background.pulse(arena.cx, arena.cy, BG.grid.waveClear)
  end
  bgResting = resting

  local fx, fy, n = 0, 0, 0
  for i = 1, world.playerCount do
    local p = world.players[i]
    if p.alive then fx, fy, n = fx + p.x, fy + p.y, n + 1 end
  end
  if n > 0 then
    bgFocusX, bgFocusY = fx / n, fy / n
  end
  Background.update(dt, bgFocusX, bgFocusY, arena.cx, arena.cy)
end

local function allPlayersOut()
  for i = 1, world.playerCount do
    if not world.players[i].out then return false end
  end
  return true
end

function Game:update(dt)
  for i = 1, world.playerCount do
    local d = world.players[i].device
    -- Controle de um jogador caiu: pausa até ele voltar.
    if d and not d.connected then
      State.push(require("src.states.pause"), world, "waiting", i)
      return
    end
    -- START e BACK abrem a pausa. Sair da partida só pelo menu de pausa
    -- (com confirmação): um toque em SELECT não pode jogar o jogador fora.
    if d and d.connected and (d:pressed("start") or
      (d:pressed("back") and not d:isDown("start"))) then
      State.push(require("src.states.pause"), world, "paused")
      return
    end
  end

  -- Hit-stop: congela a simulação por alguns frames (o desenho continua).
  if world.hitStopTimer > 0 then
    world.hitStopTimer = world.hitStopTimer - dt
    return
  end

  Spawner.update(dt, world)
  updateBackground(dt)

  -- Grid montado antes das entidades: os mísseis consultam o inimigo mais
  -- próximo por ele (Combat.update remonta depois do movimento).
  Profiler.start("collision")
  Combat.buildGrid(enemies)
  Profiler.stop("collision")

  for i = 1, world.playerCount do
    world.players[i]:update(dt, world)
  end

  world.boss:update(dt, world)

  Profiler.start("enemies")
  for i = 1, enemies.count do
    enemies.items[i]:update(dt, world)
  end
  Profiler.stop("enemies")

  -- Balas: swap-remove pelo pool, sem table.remove.
  local i = 1
  while i <= bullets.count do
    if bullets.items[i]:update(dt, world) then i = i + 1 else bullets:release(i) end
  end

  Profiler.start("particles")
  i = 1
  while i <= particles.count do
    if particles.items[i]:update(dt) then i = i + 1 else particles:release(i) end
  end
  updateRings(dt)
  Profiler.stop("particles")

  -- No respiro entre waves, todos os relógios de recompensa ficam parados:
  -- power-ups ativos, power-ups no chão e combo. Não há inimigos, então
  -- correr o relógio só desperdiçaria o que o jogador conquistou.
  local resting = Spawner.isResting()

  -- Pickups: expiram sozinhos e são coletados por contato (poucos vivos,
  -- então o teste direto contra os jogadores é mais barato que usar o grid).
  i = 1
  while i <= pickups.count do
    local pk = pickups.items[i]
    local taken = false
    if pk:update(dt, resting) then
      local r = Config.POWERUP.pickupRadius + Config.PLAYER.radius
      for pi = 1, world.playerCount do
        local p = world.players[pi]
        if p.alive and Util.dist2(pk.x, pk.y, p.x, p.y) <= r * r then
          Powerups.give(p, pk.def, world)
          Particle.burst(particles, 6, pk.x, pk.y, pk.def.color, 4)
          if Config.SMOKE then require("src.smoke").bump("pickups") end
          taken = true
          break
        end
      end
    else
      taken = true
    end
    if taken then pickups:release(i) else i = i + 1 end
  end

  if not resting then Powerups.update(dt, world) end

  Profiler.start("collision")
  Combat.update(dt, world)
  Profiler.stop("collision")
  Combo.update(dt, world, resting)

  -- Screen shake: decai rápido e é aplicado no canvas inteiro.
  if world.shakeFatigue > 0 then
    world.shakeFatigue = math.max(0, world.shakeFatigue - J.shakeFatigue.recover * dt)
  end
  if world.hitStopCooldown > 0 then world.hitStopCooldown = world.hitStopCooldown - dt end
  if world.shakeMag > 0 then
    world.shakeMag = Util.approach(world.shakeMag, 0, J.shakeDecay * dt)
    Screen.setShake(Util.randRange(-world.shakeMag, world.shakeMag),
                    Util.randRange(-world.shakeMag, world.shakeMag))
  else
    Screen.setShake(0, 0)
  end

  if allPlayersOut() then
    world:onGameOver()
    return
  end

  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.max("peakBullets", bullets.peak)
    Smoke.max("peakEnemies", enemies.peak)
    Smoke.max("peakParticles", particles.peak)
    for i2 = 1, world.playerCount do Smoke.max("combo", world.players[i2].comboBest) end
    -- Balas/inimigos recusados afetam o jogo; partículas recusadas são só
    -- efeito visual a menos (esperado em explosões grandes).
    Smoke.note("denied", bullets.denied + enemies.denied)
    Smoke.note("deniedFx", particles.denied)
  end
end

-- ---------------------------------------------------------------------------
function Game:draw()
  local C = Config.COLORS

  Background.draw()
  -- Faint grid over the sky: keeps a sense of scale, ripples on big moments.
  Background.drawGrid(arena)

  love.graphics.setColor(C.arenaLine)
  love.graphics.rectangle("line", arena.x + 0.5, arena.y + 0.5, arena.w - 1, arena.h - 1)

  Spawner.draw()

  for i = 1, pickups.count do pickups.items[i]:draw() end
  Profiler.start("particles")
  for i = 1, particles.count do particles.items[i]:draw() end
  drawRings()
  Profiler.stop("particles")
  for i = 1, enemies.count do enemies.items[i]:draw() end
  world.boss:draw()

  -- Bullets grouped by pass: enemy shots plain, an additive glow under every
  -- player shot, then each player's shots under the recolor shader in that
  -- player's color (one state switch per pass instead of one per bullet).
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner == "enemy" then b:draw() end
  end
  love.graphics.setBlendMode("add")
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" then b:drawGlow() end
  end
  love.graphics.setBlendMode("alpha")
  for p = 1, world.playerCount do
    Shaders.recolor(world.players[p].color)
    for i = 1, bullets.count do
      local b = bullets.items[i]
      if b.owner == p then b:draw() end
    end
  end
  Shaders.reset()

  for i = 1, world.playerCount do world.players[i]:draw() end

  local waveNum = numStr("wave", math.max(1, Spawner.wave), "%d")
  -- Breather countdown, keyed by tenths of a second so its string changes
  -- 10x/s, not every frame. Shared by the HUD and the wave cleared notice.
  local restNum = numStr("rest", math.floor(math.max(0, Spawner.timer) * 10 + 0.5) / 10, "%.1f")

  -- "WAVE N" banner when a wave starts, rising and fading out.
  if Spawner.banner > 0 then
    local t = Spawner.banner / Config.WAVE.bannerTime
    UI.textNumber("big", "digitsBig", "WAVE ", waveNum, nil,
      arena.cx - 160, arena.cy - 70 - (1 - t) * 10,
      { C.text[1], C.text[2], C.text[3], math.min(1, t * 2) }, 320, "center")
  end

  -- Boss alert: blinking ALERTA and the boss name while it is still offscreen.
  local boss = world.boss
  if boss.state == "warn" then
    if math.floor(boss.timer * 4) % 2 == 0 then
      UI.text("big", "ALERTA", arena.cx - 160, arena.cy - 60, C.doorWarn, 320, "center")
    end
    UI.text("title", boss.variant.name, arena.cx - 160, arena.cy - 28, C.text, 320, "center")
  end

  -- Wave cleared notice during the breather.
  if Spawner.isResting() and Spawner.wave >= 1 then
    UI.textNumber("title", "digits", "WAVE ", waveNum, " COMPLETA",
      arena.cx - 160, arena.cy - 58, C.textWarn, 320, "center")
    -- Two numbers on one centered line: measured first, then drawn in two
    -- label+number blocks.
    local bonusNum = numStr("bonus", Spawner.wave * Config.WAVE.clearBonus, "%d")
    local w1 = UI.textNumberWidth("body", "digitsSmall", "BÔNUS ", bonusNum, "   -   ")
    local w2 = UI.textNumberWidth("body", "digitsSmall", "PRÓXIMA EM ", restNum)
    local lx = arena.cx - (w1 + w2) * 0.5
    UI.textNumber("body", "digitsSmall", "BÔNUS ", bonusNum, "   -   ", lx, arena.cy - 36, C.textDim)
    UI.textNumber("body", "digitsSmall", "PRÓXIMA EM ", restNum, nil, lx + w1, arena.cy - 36, C.textDim)
  end

  -- Respawn countdown.
  for i = 1, world.playerCount do
    local p = world.players[i]
    if not p.alive and not p.out then
      UI.text("body", string.format("P%d VOLTA EM %.1f", p.index, math.max(0, p.respawnTimer)),
        arena.cx - 80, arena.cy - 22 + (i - 1) * 12, p.color, 160, "center")
    end
  end

  if showHitboxes then
    love.graphics.setColor(1, 0, 0, 0.6)
    for i = 1, enemies.count do
      local e = enemies.items[i]
      love.graphics.circle("line", e.x, e.y, e.radius)
    end
    for i = 1, bullets.count do
      local b = bullets.items[i]
      love.graphics.circle("line", b.x, b.y, b.radius)
    end
    for i = 1, world.playerCount do world.players[i]:drawDebug() end
    boss:drawDebug()
  end

  hudInfo.titleNum = waveNum
  hudInfo.boss = nil
  if Spawner.bossWave and boss.active then
    hudInfo.boss = boss
  elseif Spawner.isResting() then
    hudInfo.subLabel = "PRÓXIMA EM "
    hudInfo.subNum = restNum
  else
    hudInfo.subLabel = "INIMIGOS "
    hudInfo.subNum = numStr("enemies", Spawner.remaining(world), "%d")
  end
  Hud.draw(world.players, world.playerCount, hudInfo)

  if Config.DEBUG then
    Profiler.setCounts(enemies.count, bullets.count, particles.count)
    love.graphics.setColor(C.textDim)
    love.graphics.print(string.format("FPS %d  in %d  bal %d  par %d  neg %d/%d fx%s",
      love.timer.getFPS(), enemies.count, bullets.count, particles.count,
      bullets.denied + enemies.denied, particles.denied,
      world.godMode and "  [GOD]" or ""),
      4, Config.VIRTUAL_H - 14)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Game:keypressed(key)
  if not Config.DEBUG then return end
  if key == "f1" then
    showHitboxes = not showHitboxes
  elseif key == "f2" then
    Spawner.skipWave(world)
  elseif key == "f3" then
    world.godMode = not world.godMode
  elseif key == "f4" then
    -- Dropa um power-up aleatório no centro.
    world:dropPowerup(arena.cx, arena.cy, true)
  end
end

Game.world = world
return Game
