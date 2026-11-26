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
local RunLog   = require("src.runlog")
local Combat   = require("src.systems.combat")
local Spawner  = require("src.systems.spawner")
local Combo    = require("src.systems.combo")
local Powerups = require("src.systems.powerups")
local Upgrades = require("src.systems.upgrades")
local Pickup   = require("src.entities.pickup")
local Player   = require("src.entities.player")
local Bullet   = require("src.entities.bullet")
local Enemy    = require("src.entities.enemy")
local Boss     = require("src.entities.boss")
local Particle = require("src.entities.particle")
local Profiler = require("src.profiler")
local Shaders  = require("src.shaders")
local Post     = require("src.post")
local Assets   = require("src.assets")
local Background = require("src.background")
local UI        = require("src.ui")
local Music     = require("src.music")
local Input     = require("src.input")
local Touch     = require("src.touch")

local Game = {}

local J = Config.JUICE
local GO = Config.GAME_OVER

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
-- Particles: sized by the FX quality, set again in Game:enter (Post.load runs
-- after this module is required).
local particles = Pool.new(Particle.new, Config.FX.particles.high)
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

-- Explosion from a Config.JUICE.explosions preset (sizes times `scale`),
-- plus its thin shock ring when the preset has one.
function world:explosion(x, y, color, preset, scale)
  Particle.explosion(self.particles, x, y, color, preset, scale)
  if preset.ring then self:ring(x, y, preset.ring * (scale or 1), color, 0.35) end
end

-- Sparks bouncing back from a shot moving along (dirX, dirY) that hit.
function world:impact(x, y, dirX, dirY, color)
  Particle.impact(self.particles, x, y, dirX, dirY, color)
end

-- A ship sprite breaking into 4 spinning pieces (see Particle.debris).
function world:debris(role, x, y, angle, size, color, recolor)
  Particle.debris(self.particles, role, x, y, angle, size, color, recolor)
end

-- ---------------------------------------------------------------------------
-- Staged explosions: blasts scheduled a little later (secondary pops around
-- a big one). Fixed slots; run on game time in Game:update, so they freeze
-- in hit-stop and go slow in the game over slow motion.
-- ---------------------------------------------------------------------------
local LATER_SLOTS = 8
local later = {}
for i = 1, LATER_SLOTS do later[i] = { t = 0, x = 0, y = 0, color = nil, preset = nil, scorch = 0 } end

-- `scorch` (px, optional) leaves a burn mark there when it goes off.
function world:explodeLater(delay, x, y, color, preset, scorch)
  for i = 1, LATER_SLOTS do
    local s = later[i]
    if not s.preset then
      s.t, s.x, s.y, s.color, s.preset, s.scorch = delay, x, y, color, preset, scorch or 0
      return
    end
  end
end

-- `count` secondary `small` pops around (x, y), per a Config.JUICE.stages
-- entry; each leaves a `scorch` px burn mark if given.
function world:stagedPops(x, y, color, stage, scorch)
  local small = J.explosions.small
  for _ = 1, stage.count do
    local a = math.random() * math.pi * 2
    local r = stage.radius * math.sqrt(math.random())
    self:explodeLater(Util.randRange(stage.delayMin, stage.delayMax),
      x + math.cos(a) * r, y + math.sin(a) * r, color, small, scorch)
  end
end

local function updateLater(dt)
  for i = 1, LATER_SLOTS do
    local s = later[i]
    if s.preset then
      s.t = s.t - dt
      if s.t <= 0 then
        local preset = s.preset
        s.preset = nil
        world:explosion(s.x, s.y, s.color, preset)
        if s.scorch > 0 then world:scorch(s.x, s.y, s.scorch) end
      end
    end
  end
end

local function clearLater()
  for i = 1, LATER_SLOTS do later[i].preset = nil end
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

-- ---------------------------------------------------------------------------
-- Scorch marks (Config.FX.scorch): dark burns on the arena floor under big
-- blasts, fading out. Fixed slots, the one closest to its end is reused.
-- ---------------------------------------------------------------------------
local SC = Config.FX.scorch
local SCORCH_PUFFS = { "puff1", "puff2", "puff3", "puff4" }
local scorches = {}
for i = 1, SC.slots do scorches[i] = { x = 0, y = 0, size = 0, rot = 0, sprite = "puff1", t = SC.life } end

function world:scorch(x, y, size)
  local slot, oldest = 1, -1
  for i = 1, SC.slots do
    if scorches[i].t > oldest then slot, oldest = i, scorches[i].t end
  end
  local s = scorches[slot]
  s.x, s.y, s.size, s.t = x, y, size, 0
  s.rot = math.random() * math.pi * 2
  s.sprite = SCORCH_PUFFS[math.random(#SCORCH_PUFFS)]
end

local function updateScorches(dt)
  for i = 1, SC.slots do
    local s = scorches[i]
    if s.t < SC.life then s.t = s.t + dt end
  end
end

-- ---------------------------------------------------------------------------
-- Floating texts (Config.FX.pickup.float*): the name of a power-up rising over
-- the ship that picked it up. Fixed slots, the oldest is reused; drawn outside
-- the scene composite so they stay sharp.
-- ---------------------------------------------------------------------------
local FXP = Config.FX.pickup
-- "x2!" ... "xN!" callouts, built once (no string concat per kill).
local MULT_TEXT = {}
for m = 1, Config.COMBO.maxMult do MULT_TEXT[m] = "x" .. m .. "!" end
local FLOAT_SLOTS = 4
local floats = {}
for i = 1, FLOAT_SLOTS do floats[i] = { x = 0, y = 0, text = "", color = nil, t = FXP.floatTime } end

function world:floatText(x, y, text, color)
  local slot, oldest = 1, -1
  for i = 1, FLOAT_SLOTS do
    if floats[i].t > oldest then slot, oldest = i, floats[i].t end
  end
  local f = floats[slot]
  f.x, f.y, f.text, f.color, f.t = x, y, text, color, 0
end

local function updateFloats(dt)
  for i = 1, FLOAT_SLOTS do
    local f = floats[i]
    if f.t < FXP.floatTime then f.t = f.t + dt end
  end
end

local function clearFloats()
  for i = 1, FLOAT_SLOTS do floats[i].t = FXP.floatTime end
end

-- Rises floatRise px, pops in, fades over its second half; a 1 px dark
-- shadow keeps it readable over anything.
local function drawFloats()
  local font = Assets.font("body")
  love.graphics.setFont(font)
  for i = 1, FLOAT_SLOTS do
    local f = floats[i]
    if f.t < FXP.floatTime then
      local k = f.t / FXP.floatTime
      local a = k < 0.5 and 1 or 1 - (k - 0.5) * 2
      local sc = 1 + 0.4 * math.max(0, 1 - k * 6)          -- pop in
      local y = f.y - FXP.floatRise * (1 - (1 - k) * (1 - k))
      local w = font:getWidth(f.text)
      love.graphics.push()
      love.graphics.translate(math.floor(f.x + 0.5), math.floor(y + 0.5))
      love.graphics.scale(sc, sc)
      local x0 = -math.floor(w * 0.5)
      love.graphics.setColor(0, 0, 0, 0.8 * a)
      love.graphics.print(f.text, x0 + 1, -3)
      local c = f.color
      love.graphics.setColor(c[1], c[2], c[3], a)
      love.graphics.print(f.text, x0, -4)
      love.graphics.pop()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function clearScorches()
  for i = 1, SC.slots do scorches[i].t = SC.life end
end

-- Drawn inside the shadow layer (black, blurred with the shadows), so the
-- marks get soft edges and never get darker than a shadow. Leaves the
-- color opaque black for the casters that follow.
local function drawScorches()
  for i = 1, SC.slots do
    local s = scorches[i]
    if s.t < SC.life then
      local fade = math.min(1, (SC.life - s.t) / SC.fade)
      love.graphics.setColor(0, 0, 0, SC.alpha * fade)
      Assets.draw(s.sprite, s.x, s.y, s.rot, s.size)
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
end

-- Additive; the CALLER sets the blend. Runs in the arena pass and again in
-- the glow layer, scaled by `alphaMul`.
local function drawRings(alphaMul)
  local gr = love.graphics
  for i = 1, RING_SLOTS do
    local g = rings[i]
    if g.t < g.life then
      local k = g.t / g.life
      local c = g.color
      gr.setColor(c[1], c[2], c[3], (1 - k) * 0.9 * alphaMul)
      gr.setLineWidth(3 * (1 - k) + 1)
      gr.circle("line", g.x, g.y, g.r * (0.25 + 0.75 * k))
    end
  end
  gr.setLineWidth(1)
end

-- Everything that emits light, drawn into the glow layer (src/post.lua).
-- HUD and texts stay out of it.
local function drawGlowLayer()
  Post.beginGlow()
  Spawner.drawGlow()
  for i = 1, pickups.count do pickups.items[i]:drawGlow() end
  Particle.drawGlow(particles)
  drawRings(Config.FX.emit.ring)
  for i = 1, enemies.count do enemies.items[i]:drawTelegraph(Config.FX.emit.telegraph, arena) end
  for i = 1, enemies.count do enemies.items[i]:drawGlow() end
  world.boss:drawGlow()
  for i = 1, bullets.count do bullets.items[i]:drawGlow() end
  for i = 1, world.playerCount do world.players[i]:drawGlow() end
  Post.endGlow()
end

-- Every caster's silhouette into the shadow layer (src/post.lua), which
-- darkens the floor under them, offset down-right.
local function drawShadowLayer()
  Post.beginShadow()
  drawScorches()
  for i = 1, pickups.count do pickups.items[i]:drawShadow() end
  for i = 1, enemies.count do enemies.items[i]:drawShadow() end
  world.boss:drawShadow()
  for i = 1, world.playerCount do world.players[i]:drawShadow() end
  Post.endShadow()
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
-- Enemy shots inside the circle die with a spark; boss missiles go off.
-- No radius = the whole arena (wave end, boss death).
function world:clearEnemyShots(x, y, radius)
  local shots = self.bullets
  local r2 = radius and radius * radius
  for i = 1, shots.count do
    local b = shots.items[i]
    if b.owner == "enemy" and not b.dead
      and (not r2 or Util.dist2(x, y, b.x, b.y) <= r2) then
      b.dead = true
      if b.kind == "bossMissile" then
        b:blast(self)
      else
        Particle.burst(self.particles, 2, b.x, b.y, b.color, 3)
      end
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
  Post.shockwave(p.x, p.y, Config.FX.shock.nova, NV.radius)
  self:shake(4)
end

-- CHOQUE: a mini-NOVA around the player at the end (and start) of a dash.
function world:shockPulse(p, radius, dmg)
  local SH = Config.UPGRADES.shock
  self:areaDamage(p.x, p.y, radius, dmg, p.index)
  self:clearEnemyShots(p.x, p.y, radius)
  self:ring(p.x, p.y, radius, p.color, 0.35)
  self:ring(p.x, p.y, radius * 0.6, Config.COLORS.flash, 0.25)
  Particle.burst(self.particles, 6, p.x, p.y, p.color, 4)
  Post.shockwave(p.x, p.y, Config.FX.shock.bubble, radius)
  self:shake(1.5)
  Audio.play("nova", SH.volume, SH.pitch)
  if Config.SMOKE then require("src.smoke").bump("shocks") end
end

-- A respawn salvo missile going off: its own hit already dealt `dmg`; the
-- blast hurts everything around.
function world:salvoBlast(b)
  local S = RS.salvo
  self:areaDamage(b.x, b.y, S.blastRadius, S.blastDamage, b.owner)
  self:explosion(b.x, b.y, b.color, J.explosions.salvo)
  self:ring(b.x, b.y, S.blastRadius, b.color, 0.3)
  Post.shockwave(b.x, b.y, Config.FX.shock.salvo, S.blastRadius)
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
  Post.shockwave(p.x, p.y, Config.FX.shock.bubble, BB.pushRadius)
  Particle.burst(self.particles, 10, p.x, p.y, { 0.60, 0.95, 1.00, 1 }, 4)
  Audio.play("bubble_pop")
  -- RECARGA++: the bubble pops with a NOVA.
  if p.mods.popNova then self:nova(p) end
end

-- The boss died: every enemy blows up (no points) and every enemy shot pops.
-- Enemies leave the pool right away (flagged dead first, so collision
-- queries this frame skip them); bullets are flagged and swept by Combat, so
-- this is safe to call from inside the collision loops.
function world:clearHostiles()
  local pool = self.enemies
  for i = pool.count, 1, -1 do
    local e = pool.items[i]
    self:explosion(e.x, e.y, e.color, J.explosions.small)
    e.dead = true
    pool:release(i)
  end
  self:clearEnemyShots()
  Spawner.subboss = nil
end

-- Missile smoke: skipped while the pool is busy, so explosions keep priority.
function world:trail(x, y, color)
  local pool = self.particles
  if pool.count >= pool.capacity * J.trailPoolShare then return end
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

-- Divisor: its pieces fan out from where it died, harmless for a moment.
-- Straight into the pool (not through the spawner): outside the wave quota,
-- still counted as alive; none when the pool is full.
function world:split(enemy)
  local def = enemy.def
  local kind = def.splitInto
  local child = Config.ENEMIES[kind]
  local n = def.splitCount
  local start = math.random() * math.pi * 2
  for i = 1, n do
    local ang = start + (i - 1) / n * math.pi * 2
    local e = self:spawnEnemy(kind, enemy.x, enemy.y)
    if not e then break end
    e.vx, e.vy = math.cos(ang) * def.splitSpeed, math.sin(ang) * def.splitSpeed
    e.angle = ang
    e.harmless = child.harmlessTime or 0
  end
  Audio.play("divisor_split")
  if Config.SMOKE then require("src.smoke").bump("splits") end
end

-- Carrier: its drones blow up with it (no points, drops or combo). Flagged
-- dead; Combat's sweep takes them out of the pool at the end of the frame.
function world:killBrood(enemy)
  local pool = self.enemies
  local any = false
  for i = 1, pool.count do
    local e = pool.items[i]
    if e.parent == enemy and not e.dead then
      local size = Config.ART.size[e.type] or e.def.size
      self:explosion(e.x, e.y, e.color, J.explosions.small, size / Config.ART.size.grunt)
      e.dead = true
      e.parent = nil
      any = true
    end
  end
  if any then Audio.play("enemy_die") end
end

-- Sub-boss down (Config.SUBBOSS): its guaranteed power-ups around the
-- wreck and a boss-like (smaller) finale. Its points are in onEnemyKilled.
function world:subbossDown(enemy)
  local S = Config.SUBBOSS
  local a, m = self.arena, Config.POWERUP.dropMargin
  for i = 1, S.drops do
    local ang = (i - 1) / S.drops * math.pi * 2 + math.random() * 0.6
    local x = Util.clamp(enemy.x + math.cos(ang) * 26, a.x + m, a.x + a.w - m)
    local y = Util.clamp(enemy.y + math.sin(ang) * 26, a.y + m, a.y + a.h - m)
    self:dropPowerup(x, y, true)
  end
  self:explosion(enemy.x, enemy.y, enemy.color, J.explosions.boss, S.deathScale)
  self:stagedPops(enemy.x, enemy.y, enemy.color, J.stages.player)
  Post.shockwave(enemy.x, enemy.y, Config.FX.shock.player)
  self:shake(S.deathShake, true)
  self:hitStop(S.deathHitStop, true)
  Audio.play("boss_die", 0.8, 0.9)
  if Spawner.subboss == enemy then Spawner.subboss = nil end
  if Config.SMOKE then require("src.smoke").bump("subbosses") end
end

function world:onEnemyKilled(enemy, killerIndex)
  local size = Config.ART.size[enemy.type] or enemy.def.size
  -- Heavy ships (tank, carrier: the ones with an HP bar) go out big.
  local heavy = enemy.def.hpBar
  if heavy then
    self:explosion(enemy.x, enemy.y, enemy.color, J.explosions.tank)
    self:debris(enemy.type, enemy.x, enemy.y, enemy.angle, size, enemy.color, false)
    self:scorch(enemy.x, enemy.y, Config.FX.scorch.tank)
  else
    -- Small ships: the same preset, scaled by the sprite size (grunt = 1).
    self:explosion(enemy.x, enemy.y, enemy.color, J.explosions.small, size / Config.ART.size.grunt)
  end

  -- Combo sobe primeiro: a morte já conta com o multiplicador novo.
  if type(killerIndex) == "number" then
    local killer = self.players[killerIndex]
    if killer then
      if Combo.add(killer) and killer.alive then
        -- Multiplier up: "xN!" rises over the ship.
        self:floatText(killer.x, killer.y - 14, MULT_TEXT[Combo.mult(killer)], Config.COLORS.textWarn)
      end
      local pts = enemy.def.points * (enemy.elite and Config.ELITE.pointsMul or 1)
        * math.max(1, enemy.subN)   -- sub-boss: x its order in the match
      self:addScore(killerIndex, pts * Combo.mult(killer))
    end
  end

  self:dropPowerup(enemy.x, enemy.y, false)
  if enemy.def.splitInto then self:split(enemy) end
  if enemy.def.spawn then self:killBrood(enemy) end
  if enemy.def.subboss then self:subbossDown(enemy) end

  if heavy then
    self:shake(J.shakeTankDeath)
    Background.pulse(enemy.x, enemy.y, Config.ART.background.grid.tankDeath)
    Post.shockwave(enemy.x, enemy.y, Config.FX.shock.tank)
    self:hitStop(J.hitStopTank)
    Audio.play("tank_die")
  else
    self:shake(J.shakeEnemyDeath)
    Audio.play("enemy_die")
  end

  if Config.SMOKE then require("src.smoke").bump("kills") end
end

function world:onPlayerHit(player, cause)
  -- One hit per moment: the bubble's invulnerability also covers the other
  -- collision checks of the same frame.
  if not player.alive or player.invuln > 0 or player:dashGuarded() then return end
  if player.mods.bubble then
    popBubble(self, player)
    return
  end
  player.alive = false
  RunLog.death(player, cause)
  player.lives = player.lives - 1
  Combo.breakOn(player)
  -- Staged: the big blast, the ship in pieces, then a few secondary pops.
  self:explosion(player.x, player.y, player.color, J.explosions.player)
  self:debris("playerShip", player.x, player.y, player.angle, Config.ART.size.playerShip,
    player.color, true)
  self:stagedPops(player.x, player.y, player.color, J.stages.player)
  self:scorch(player.x, player.y, Config.FX.scorch.player)
  Post.shockwave(player.x, player.y, Config.FX.shock.player)
  Post.aberrate(Config.FX.aberration.player)
  Post.hurt(1)
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
  -- The jingle already played over the arena: the results screen only
  -- brings the music in, timed from it.
  summary.sinceJingle = world.endJingle and (world.endT - Config.GAME_OVER.textDelay) or nil

  local beat = Save.submitMatch(self.playerCount, summary.scores)
  summary.beat.solo, summary.beat.duo, summary.beat.coop = beat.solo, beat.duo, beat.coop

  -- Shake is only updated by the arena: clear it or the next screen inherits
  -- the last frame's offset.
  Screen.setShake(0, 0)
  require("src.transition").start()   -- wipe into the results
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
  self:ring(x, y, Config.FX.pickup.dropRing, def.color, 0.35)   -- drop pop
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
  goWave = { v = nil, s = "" }, goScore1 = { v = nil, s = "" }, goScore2 = { v = nil, s = "" },
}
local function numStr(slot, value, fmt)
  local c = numCache[slot]
  if c.v ~= value then
    c.v = value
    c.s = string.format(fmt, value)
  end
  return c.s
end

-- Wave banners (Config.FX.hud): centered label+number text that pops in
-- (from bannerPopScale down to 1 over bannerPop s, eased out) around its
-- center, `half` px below `y`, and gets a light band sweeping it left to
-- right between sweepStart and sweepStart + sweepTime (the same glyphs
-- redrawn additively through the sheen shader). `age` = s since it appeared.
local bannerColor = { 1, 1, 1, 1 }
local sweepColor = { 1, 1, 1, 1 }
local introColor = { 1, 1, 1, 1 }   -- debut line under the banner

local function drawBannerText(fontRole, digitRole, label, num, suffix, y, half, age, color)
  local HC = Config.FX.hud
  local g = love.graphics
  local k = math.min(1, age / HC.bannerPop)
  local sc = 1 + (HC.bannerPopScale - 1) * (1 - k) * (1 - k)
  local cx, cy = arena.cx, y + half
  g.push()
  g.translate(cx, cy)
  g.scale(sc, sc)
  UI.textNumber(fontRole, digitRole, label, num, suffix, -160, -half, color, 320, "center")
  g.pop()
  local s = (age - HC.sweepStart) / HC.sweepTime
  if s > 0 and s < 1 then
    local w = UI.textNumberWidth(fontRole, digitRole, label, num, suffix)
    local bx = cx - w * 0.5 - 20 + (w + 40) * s
    if Shaders.sheenAt(bx, cy, HC.sweepWidth) then
      sweepColor[4] = color[4] or 1
      g.setBlendMode("add")
      g.push()
      g.translate(cx, cy)
      g.scale(sc, sc)
      UI.textNumber(fontRole, digitRole, label, num, suffix, -160, -half, sweepColor, 320, "center")
      g.pop()
      g.setBlendMode("alpha")
      Shaders.reset()
    end
  end
end

-- Game over over the still-running arena: dims it, then GAME OVER, the wave
-- reached and each score (in the player's color), and a blinking START.
local goColor = { 1, 1, 1, 1 }
local function faded(c, a)
  goColor[1], goColor[2], goColor[3], goColor[4] = c[1], c[2], c[3], (c[4] or 1) * a
  return goColor
end

local function drawGameOver()
  if world.endT < GO.textDelay then return end
  local C = Config.COLORS
  local a = math.min(1, (world.endT - GO.textDelay) / GO.fadeIn)
  local g = love.graphics
  g.setColor(0, 0, 0, GO.dim * a)
  g.rectangle("fill", arena.x, arena.y, arena.w, arena.h)

  local cx, cy = arena.x, arena.cy
  UI.text("big", "GAME OVER", cx, cy - 46, faded(C.doorWarn, a), arena.w, "center")
  UI.textNumber("title", "digits", "WAVE ", numStr("goWave", Spawner.wave, "%d"), nil,
    cx, cy - 14, faded(C.text, a), arena.w, "center")

  if world.playerCount >= 2 then
    for i = 1, 2 do
      local p = world.players[i]
      local s = numStr(i == 1 and "goScore1" or "goScore2", p.score, "%07d")
      UI.digits("digits", s, arena.cx + (i == 1 and -150 or 10), cy + 10, faded(p.color, a), 140, "center")
    end
  else
    UI.digits("digits", numStr("goScore1", world.players[1].score, "%07d"),
      cx, cy + 10, faded(C.text, a), arena.w, "center")
  end

  if Game.endAccepting() and math.floor(world.endT * 2.5) % 2 == 0 then
    UI.text("title", Input.usingTouch() and "TOQUE NA TELA" or "APERTE START",
      cx, cy + 44, C.text, arena.w, "center")
  end
  g.setColor(1, 1, 1, 1)
end

-- Player playing on the touch screen, if any.
local function touchPlayer()
  for i = 1, world.playerCount do
    local p = world.players[i]
    if p.device and p.device.kind == "touch" then return p end
  end
  return nil
end

-- Pause button (touch): a small panel with two bars, right of the WAVE title.
local function drawPauseButton()
  local s = Config.TOUCH.pauseSize
  local tw = UI.textNumberWidth("title", "digits", hudInfo.titleLabel, hudInfo.titleNum)
  local x = math.floor(Config.VIRTUAL_W * 0.5 + tw * 0.5 + 10)
  local y = 3
  UI.panel(x, y, s, s)
  local g = love.graphics
  g.setColor(Config.COLORS.text)
  local bw, bh = 3, s * 0.5
  g.rectangle("fill", x + s * 0.5 - bw - 1.5, y + (s - bh) * 0.5, bw, bh)
  g.rectangle("fill", x + s * 0.5 + 1.5, y + (s - bh) * 0.5, bw, bh)
  g.setColor(1, 1, 1, 1)
  Touch.button("start", x, y, s, s)
end

-- DASH button (touch): a disc above the aim ghost, filling up with the
-- player's cooldown; a finger landing on it dashes instead of aiming.
local dashTextColor = { 1, 1, 1, 1 }

local function drawDashButton(p)
  local T = Config.TOUCH
  local r = T.dashRadius
  local x = Config.VIRTUAL_W - T.ghostInset
  local y = Config.VIRTUAL_H - T.ghostInset - T.dashLift
  local g = love.graphics
  local c = p.color
  local ready = p.dashCd <= 0
  local k = ready and 1 or 1 - p.dashCd / p.dashCdMax
  g.setColor(c[1], c[2], c[3], ready and 0.28 or 0.12)
  g.circle("fill", x, y, r)
  if not ready then
    g.setColor(c[1], c[2], c[3], 0.25)
    g.arc("fill", x, y, r, -math.pi / 2, -math.pi / 2 + k * math.pi * 2, 24)
  end
  g.setColor(c[1], c[2], c[3], ready and 0.8 or 0.4)
  g.setLineWidth(1.5)
  g.circle("line", x, y, r)
  g.setLineWidth(1)
  local C = Config.COLORS.text
  dashTextColor[1], dashTextColor[2], dashTextColor[3] = C[1], C[2], C[3]
  dashTextColor[4] = ready and 0.9 or 0.45
  UI.text("body", "DASH", x - r, y - 4, dashTextColor, r * 2, "center")
  g.setColor(1, 1, 1, 1)
  Touch.button("dash", x - r, y - r, r * 2, r * 2)
end

function Game:enter(devices, count)
  world.playerCount = count or 1
  world.players = {}
  world.shakeMag = 0
  world.shakeFatigue = 0
  world.hitStopTimer = 0
  world.hitStopCooldown = 0
  world.endT = -1          -- game over sequence: real s since the last death
  world.endJingle = false
  world.godMode = Config.SMOKE_GOD or false
  bullets:clear()
  enemies:clear()
  particles:clear()
  pickups:clear()
  world.boss:clear()
  Post.clear()
  clearLater()
  clearScorches()
  clearFloats()
  particles.capacity = Post.particleCap()
  Spawner.load(arena)
  Spawner.reset(world, Config.SMOKE_WAVE)
  -- Sky set straight to the starting wave's palette (--wave 25 starts there).
  Background.reset(Background.themeForWave(Spawner.wave + 1))
  bgWave, bgResting = Spawner.wave, true
  bgFocusX, bgFocusY = arena.cx, arena.cy

  for i = 1, world.playerCount do
    local p = Player.new(i, devices[i])
    local dx = world.playerCount == 1 and 0 or (i == 1 and -30 or 30)
    p:place(arena.cx + dx, arena.cy)   -- beams in when the briefing closes
    Combo.reset(p)
    world.players[i] = p
    -- --upgrades N: start with N random picks (normal and boss offers
    -- alternating), to try builds without playing up to them.
    for k = 1, Config.START_UPGRADES or 0 do
      Upgrades.randomTake(p, k % 2 == 0)
    end
  end

  -- A arena já está montada; o briefing fica por cima (tudo congelado) até
  -- alguém apertar START.
  RunLog.begin(world)
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

-- ---------------------------------------------------------------------------
-- Game over sequence (Config.GAME_OVER): the last explosion plays in slow
-- motion, the arena keeps running with the doors closed, GAME OVER shows
-- after textDelay and START goes to the results screen.
-- ---------------------------------------------------------------------------

local function beginGameOver()
  world.endT = 0
  RunLog.finish(world, "fim")
  world.endJingle = false
  Spawner.stop()
  Music.stop()             -- fades out
end

local function gameOverTimeScale(t)
  if t < GO.slowHold then return GO.slowMo end
  local k = (t - GO.slowHold) / GO.slowEase
  if k >= 1 then return 1 end
  return GO.slowMo + (1 - GO.slowMo) * k
end

function Game.isEnding()
  return world.endT >= 0
end

-- START works once the text has been up for acceptDelay.
function Game.endAccepting()
  return world.endT >= GO.textDelay + GO.acceptDelay
end

-- Window/tab lost focus (another app on the phone, alt-tab): pause. Not
-- during the game over, and never in the smoke run (the bot would unpause).
function Game:focus(focused)
  if focused or world.endT >= 0 or Config.SMOKE then return end
  State.push(require("src.states.pause"), world, "paused")
end

-- Leaving the arena: to the results (the run log already closed the match
-- at the last death) or quitting from the pause menu (closes it as quit).
function Game:leave()
  RunLog.finish(world, "abandono")
end

function Game:update(dt)
  local ending = world.endT >= 0
  if ending then
    world.endT = world.endT + dt
    if not world.endJingle and world.endT >= GO.textDelay then
      world.endJingle = true
      Audio.play("game_over")
    end
    dt = dt * gameOverTimeScale(world.endT)
  else
    RunLog.tick(dt)   -- match time (no pause, no overlay: they skip this update)
  end

  for i = 1, world.playerCount do
    local d = world.players[i].device
    -- Controle de um jogador caiu: pausa até ele voltar.
    if d and not d.connected then
      State.push(require("src.states.pause"), world, "waiting", i)
      return
    end
    if ending then
      -- No pause during the game over: START goes to the results.
      if d and d.connected and d:pressed("start") and Game.endAccepting() then
        world:onGameOver()
        return
      end
    -- START e BACK abrem a pausa. Sair da partida só pelo menu de pausa
    -- (com confirmação): um toque em SELECT não pode jogar o jogador fora.
    elseif d and d.connected and (d:pressed("start") or
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

  -- Upgrade pick (every UPGRADES.every waves): opens openDelay s into the
  -- breather, over the frozen arena (the breather countdown waits for it).
  if Spawner.upgradeDue and Spawner.isResting() and not ending
    and Config.WAVE.restTime - Spawner.timer >= Config.UPGRADES.openDelay then
    Spawner.upgradeDue = false
    State.push(require("src.states.upgrade"), world, Spawner.isBossWave(Spawner.wave))
    return
  end

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
  updateScorches(dt)
  updateFloats(dt)
  Profiler.stop("particles")
  Post.update(dt)   -- game time: waves freeze in hit-stop, slow in the game over
  updateLater(dt)   -- staged explosions, same clock

  -- No respiro entre waves, todos os relógios de recompensa ficam parados:
  -- power-ups ativos, power-ups no chão e combo. Não há inimigos, então
  -- correr o relógio só desperdiçaria o que o jogador conquistou. On a boss
  -- wave the same holds while the boss can't be hit (alert, entry, death).
  local frozen = Spawner.isResting()
    or (Spawner.bossWave and not world.boss:isFighting())

  -- Pickups: expiram sozinhos e são coletados por contato (poucos vivos,
  -- então o teste direto contra os jogadores é mais barato que usar o grid).
  i = 1
  while i <= pickups.count do
    local pk = pickups.items[i]
    local taken = false
    if pk:update(dt, frozen) then
      local r = Config.POWERUP.pickupRadius + Config.PLAYER.radius
      -- ÍMÃ: a pickup within a player's magnet radius drifts to the ship.
      for pi = 1, world.playerCount do
        local p = world.players[pi]
        local mr = p.mods.magnet
        if p.alive and mr > 0 then
          local dx, dy = p.x - pk.x, p.y - pk.y
          local d2 = dx * dx + dy * dy
          if d2 <= mr * mr and d2 > 0.01 then
            local d = math.sqrt(d2)
            local step = math.min(d, Config.UPGRADES.magnet.pull * dt)
            pk.x, pk.y = pk.x + dx / d * step, pk.y + dy / d * step
            break
          end
        end
      end
      for pi = 1, world.playerCount do
        local p = world.players[pi]
        if p.alive and Util.dist2(pk.x, pk.y, p.x, p.y) <= r * r then
          Powerups.give(p, pk.def, world)
          Particle.burst(particles, 6, pk.x, pk.y, pk.def.color, 4)
          world:ring(p.x, p.y, FXP.collectRing, pk.def.color, 0.35)
          world:floatText(p.x, p.y - 14, pk.def.name, pk.def.color)
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

  if not frozen then Powerups.update(dt, world) end

  Profiler.start("collision")
  Combat.update(dt, world)
  Profiler.stop("collision")
  Combo.update(dt, world, frozen)
  Hud.update(dt, world.players, world.playerCount)   -- score run-up, punches

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

  if world.endT < 0 and allPlayersOut() then beginGameOver() end

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
-- `covered`: a pause/briefing is drawn on top (it owns the touch input).
function Game:draw(covered)
  local C = Config.COLORS

  -- The arena (sky to glow) goes through the scene composite (shockwaves,
  -- aberration, vignette); banners, texts and the HUD stay out of it.
  Post.beginScene()
  Background.draw()
  -- The sky steps back during a match (the lobby keeps it vivid).
  love.graphics.setColor(0, 0, 0, Config.FX.veil)
  love.graphics.rectangle("fill", 0, 0, Config.VIRTUAL_W, Config.VIRTUAL_H)
  -- Faint grid over the sky: keeps a sense of scale, ripples on big moments.
  Background.drawGrid(arena)

  love.graphics.setColor(C.arenaLine)
  love.graphics.rectangle("line", arena.x + 0.5, arena.y + 0.5, arena.w - 1, arena.h - 1)

  Spawner.draw()

  -- The floor: burn marks and every caster's shadow (one blurred layer),
  -- then the ships above.
  drawShadowLayer()

  for i = 1, pickups.count do pickups.items[i]:draw() end
  Profiler.start("particles")
  Particle.drawUnder(particles)   -- smoke, trails, debris: under the enemies
  love.graphics.setBlendMode("add")
  drawRings(1)
  love.graphics.setBlendMode("alpha")
  Profiler.stop("particles")
  -- Kamikaze aim lines and runner afterimages under every live enemy, then
  -- the enemies.
  for i = 1, enemies.count do enemies.items[i]:drawTelegraph(1, arena) end
  for i = 1, enemies.count do enemies.items[i]:drawEchoes() end
  for i = 1, enemies.count do enemies.items[i]:draw() end
  world.boss:draw()

  -- Bullets grouped by pass: enemy shots plain, then the smear behind every
  -- player shot (additive, one texture: batched), then each player's shots
  -- under the recolor shader in that player's color (one state switch per
  -- pass instead of one per bullet). Their light is in the glow layer.
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner == "enemy" then b:draw() end
  end
  love.graphics.setBlendMode("add")
  for i = 1, bullets.count do bullets.items[i]:drawTrail(1) end
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

  -- Fire, sparks and flashes over everything in the arena (they are light:
  -- they never hide what is alive).
  Profiler.start("particles")
  Particle.drawOver(particles)
  Profiler.stop("particles")

  drawGlowLayer()
  Post.endScene(arena)
  drawFloats()   -- picked power-up names: sharp, over the arena

  local waveNum = numStr("wave", math.max(1, Spawner.wave), "%d")
  -- Breather countdown, keyed by tenths of a second so its string changes
  -- 10x/s, not every frame. Shared by the HUD and the wave cleared notice.
  local restNum = numStr("rest", math.floor(math.max(0, Spawner.timer) * 10 + 0.5) / 10, "%.1f")

  -- "WAVE N" banner when a wave starts: pops in, a light band sweeps it,
  -- then it rises and fades out.
  if Spawner.banner > 0 then
    local t = Spawner.banner / Config.WAVE.bannerTime
    local age = Config.WAVE.bannerTime - Spawner.banner
    local by = arena.cy - 70 - (1 - t) * 10
    local tint = Config.FX.hud.bannerTint
    bannerColor[1], bannerColor[2], bannerColor[3], bannerColor[4] = tint[1], tint[2], tint[3], math.min(1, t * 2)
    drawBannerText("big", "digitsBig", "WAVE ", waveNum, nil, by, 12, age, bannerColor)
    -- A type's debut wave: "NOVO: <NAME>" under it, in that enemy's color.
    if Spawner.introLabel then
      local ec = Config.COLORS[Config.ENEMIES[Spawner.introType].color]
      introColor[1], introColor[2], introColor[3], introColor[4] = ec[1], ec[2], ec[3], bannerColor[4]
      UI.text("title", Spawner.introLabel, arena.cx - 160, by + 30, introColor, 320, "center")
    end
  end

  -- Boss alert: blinking ALERTA and the boss name while it is still offscreen.
  local boss = world.boss
  if boss.state == "warn" then
    if math.floor(boss.timer * 4) % 2 == 0 then
      UI.text("big", "ALERTA", arena.cx - 160, arena.cy - 60, C.doorWarn, 320, "center")
    end
    UI.text("title", boss.variant.name, arena.cx - 160, arena.cy - 28, C.text, 320, "center")
  end
  -- Sub-boss alert: shorter and faster than the boss's, in the title font.
  if Spawner.subAlert > 0 and Spawner.subName then
    if math.floor(Spawner.subAlert * 8) % 2 == 0 then
      UI.text("title", "ALERTA", arena.cx - 160, arena.cy - 60, C.doorWarn, 320, "center")
    end
    UI.text("title", Spawner.subName, arena.cx - 160, arena.cy - 40, C.text, 320, "center")
  end

  -- Wave cleared notice during the breather.
  if Spawner.isResting() and Spawner.wave >= 1 then
    local age = Config.WAVE.restTime - Spawner.timer
    drawBannerText("title", "digits", "WAVE ", waveNum, " COMPLETA", arena.cy - 58, 8, age, C.textWarn)
    -- Two numbers on one centered line: measured first, then drawn in two
    -- label+number blocks. The bonus counts up from 0.
    local HC = Config.FX.hud
    local kb = math.min(1, age / HC.bonusCount)
    kb = 1 - (1 - kb) * (1 - kb)
    local bonusNum = numStr("bonus", math.floor(Spawner.wave * Config.WAVE.clearBonus * kb + 0.5), "%d")
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
  hudInfo.sub = nil
  local sub = Spawner.subboss
  if Spawner.bossWave and boss.active then
    hudInfo.boss = boss
  elseif sub and not sub.dead and sub.def.subboss then
    hudInfo.sub = sub   -- its name and HP bar in place of the enemy count
  elseif Spawner.isResting() then
    hudInfo.subLabel = "PRÓXIMA EM "
    hudInfo.subNum = restNum
  else
    hudInfo.subLabel = "INIMIGOS "
    hudInfo.subNum = numStr("enemies", Spawner.remaining(world), "%d")
  end
  -- Touch: the sticks under the HUD, the pause button beside the WAVE title.
  local tp = not covered and world.endT < 0 and touchPlayer()
  if tp then
    Touch.useSticks()
    Touch.drawSticks(tp.color)
    drawDashButton(tp)
  end
  Hud.draw(world.players, world.playerCount, hudInfo)
  if tp then drawPauseButton() end
  drawGameOver()

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
  elseif key == "f8" then
    -- The sub-boss of the current cycle, right now, through a door.
    Spawner.spawnSubboss(world)
  elseif key == "f7" then
    -- Upgrade screen right now (a normal offer; shift = a boss offer).
    State.push(require("src.states.upgrade"), world, love.keyboard.isDown("lshift", "rshift"))
  elseif key == "f6" then
    -- Test shockwave + aberration at the center (tuning Config.FX).
    Post.shockwave(arena.cx, arena.cy, Config.FX.shock.debug)
    Post.aberrate(Config.FX.aberration.debug)
  end
end

Game.world = world
return Game
