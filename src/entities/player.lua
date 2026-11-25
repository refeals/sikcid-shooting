-- Jogador. Não é pooled: existem no máximo 2 instâncias, criadas no início
-- da partida. Lê input SÓ do seu device (self.device).

local Config  = require("src.config")
local Util    = require("src.util")
local Audio   = require("src.audio")
local Assets  = require("src.assets")
local Shaders = require("src.shaders")
local UI      = require("src.ui")
local Post    = require("src.post")
local Upgrades = require("src.systems.upgrades")
local Combat  = require("src.systems.combat")

local P = Config.PLAYER
local W = Config.WEAPON
local R = Config.RESPAWN
local DR = Config.POWERUPS.drone
local SIZE = Config.ART.size
local TR = Config.FX.trail
local MZ = Config.FX.muzzle
local D = Config.DASH

local UP = -math.pi / 2
local BUBBLE_COLOR = { 0.60, 0.95, 1.00 }

local Player = {}
Player.__index = Player

-- Damage of one shot: the weapon's base damage times the DANO X2 multiplier.
local function shotDamage(self)
  return self.mods.damage * self.mods.damageMul
end

-- Every player shot goes through here: flags it `powered` under DANO X2, so
-- it is drawn bigger and hotter and sparks on impact.
-- PERFURANTE: every player shot carries the pierce count (see Combat).
local function fire(self, world, x, y, dx, dy, speed, dmg, kind, life, radius)
  local b = world:spawnBullet(x, y, dx, dy, speed, dmg, self.index, kind, life, radius, self.color)
  if b then
    local m = self.mods
    if m.damageMul > 1 then b.powered = true end
    b.pierce = m.pierce
    b.bounces, b.bounceHoming = m.bounces, m.bounceHoming   -- RICOCHETE
  end
  return b
end

-- Armas disponíveis, indexadas por mods.weapon. As etapas seguintes só
-- acrescentam entradas aqui; nada de `if` espalhado pelo update.
local WEAPONS = {}

WEAPONS.single = function(self, world)
  fire(self, world, self.x, self.y, self.aimX, self.aimY, W.bulletSpeed, shotDamage(self), "single")
  Audio.play("shot")
end

-- Spread: leque de W.spreadCount balas cobrindo W.spreadAngle.
WEAPONS.spread = function(self, world)
  local base = math.atan2(self.aimY, self.aimX)
  local n = W.spreadCount
  local step = n > 1 and (W.spreadAngle / (n - 1)) or 0
  local start = base - W.spreadAngle * 0.5
  for i = 1, n do
    local a = start + step * (i - 1)
    fire(self, world, self.x, self.y, math.cos(a), math.sin(a), W.bulletSpeed, shotDamage(self), "spread")
  end
  Audio.play("shot_spread")
end

-- Missiles: projétil lento que corrige a rota até o inimigo mais próximo.
WEAPONS.missiles = function(self, world)
  fire(self, world, self.x, self.y, self.aimX, self.aimY, W.missileSpeed, shotDamage(self),
    "missile", W.bulletLife * 2, W.bulletRadius + 1)
  Audio.play("shot_missile")
end

function Player.new(index, device)
  local self = setmetatable({
    index = index,
    device = device,
    color = Config.PLAYER_COLORS[index],
    x = 0, y = 0,
    vx = 0, vy = 0,
    aimX = 0, aimY = -1,      -- mira inicial: para cima
    angle = UP,               -- drawn facing; eases toward the aim
    engineT = 0,              -- drives the engine flame flicker
    lives = P.lives,
    score = 0,
    alive = true,
    out = false,              -- zerou as vidas: fica de fora até o fim
    invuln = 0,
    respawnTimer = 0,
    fireCooldown = 0,
    target = nil,             -- enemy locked by the auto-aim
    muzzle = 0,               -- clarão curto do cano ao atirar
    spawnFx = 0,              -- anel de respawn
    -- Drones (DRONE power-up + DRONE FIEL upgrade): up to MAX_DRONES spaced
    -- evenly on one orbit. Per slot: fire timer, barrel direction (last
    -- target), muzzle flash and fire rate multiplier. Fixed arrays.
    droneAngle = 0,
    droneN = 0,
    droneCd = { 0, 0, 0 },
    droneAimX = { 0, 0, 0 }, droneAimY = { -1, -1, -1 },
    droneFlash = { 0, 0, 0 },
    droneRate = { 1, 1, 1 },
    -- Permanent upgrades (src/systems/upgrades.lua): id -> level, and the ids
    -- in the order they were first taken (HUD).
    upgrades = {},
    upgradeOrder = {},
    maxLives = P.maxLives,    -- CASCO raises it
    rearCooldown = 0,         -- RETAGUARDA fire timer
    rechargeT = 0,            -- RECARGA: s without a bubble so far
    -- LÂMINA: enemies already cut by the current dash (once each), and
    -- whether the boss was.
    bladeHits = {}, bladeN = 0, bladeBoss = false,
    -- Respawn marker (while dead with lives left): where the ship comes back.
    markerX = 0, markerY = 0,
    markerDelay = 0,          -- hidden (and still) for this long after the death
    revived = false,          -- set by the spawner: back after running out (no support)
    mods = {},
    powerups = {},            -- { { def = <DEF>, timeLeft = s }, ... }
    -- Engine ribbon (Config.FX.trail): the ship's tail sampled every
    -- ribbonEvery s, newest first; `ribbonN` points in use. Fixed arrays and
    -- one mesh, reused every frame.
    ribbonX = {}, ribbonY = {}, ribbonAt = {},
    ribbonN = 0, ribbonT = 0,
    ribbonClock = 0,          -- game time, runs while dead too (the ribbon fades)
    hidden = false,           -- match start: not drawn until :arrive (briefing)
    -- Dash (Config.DASH): see Player:updateDash.
    dashT = 0,                -- s of burst left
    dashSafe = 0,             -- s of protection left (burst + grace)
    dashCd = 0,               -- s until the next dash
    dashCdMax = D.cooldown,   -- the full cooldown of the last dash (PROPULSOR)
    dashBuffer = 0,           -- an early press, still waiting for the cooldown
    dashDX = 0, dashDY = 0,   -- burst direction
    dashLinger = 0,           -- s of protection left to spend inside an enemy
    dashLingering = false,    -- burst over, still inside an enemy
    dashTouched = false,      -- set by Combat: touching an enemy while lingering
    readyFlash = 0,           -- cooldown ring flash when the dash is back
    -- Dash afterimages: fixed arrays, newest first, aged by ghostAt.
    ghostX = {}, ghostY = {}, ghostA = {}, ghostAt = {},
    ghostN = 0, ghostT = 0,
  }, Player)
  self:resetMods()
  self.ribbonMesh = love.graphics.newMesh((TR.ribbonPoints + 1) * 2, "strip", "stream")
  return self
end

-- Valores base da arma/movimento. The permanent upgrades write their layer
-- here; the power-ups reapply on top of it.
function Player:resetMods()
  local m = self.mods
  m.speedMul = 1
  m.fireRateMul = 1
  m.damage = W.damage
  m.damageMul = 1
  m.weapon = "single"
  m.bubble = false
  m.drone = false
  m.dashCdMul = 1       -- PROPULSOR
  m.durationMul = 1     -- DURAÇÃO
  m.magnet = 0          -- ÍMÃ: pull radius (px)
  m.pierce = 0          -- PERFURANTE: extra enemies a shot passes through
  m.rearRate = 0        -- RETAGUARDA: rear fire rate (x the main one), 0 = off
  m.rearFan = 1         -- RETAGUARDA: rear shots per volley
  m.loyalCount = 0      -- DRONE FIEL: permanent drones
  m.loyalRate = 0       -- DRONE FIEL: their fire rate (x the power-up drone's)
  m.blade = 0           -- LÂMINA: dash damage (0 = off)
  m.bladeReset = false  -- LÂMINA++: a blade kill recharges the dash
  m.recharge = 0        -- RECARGA: s between free bubbles (0 = off)
  m.popNova = false     -- RECARGA++: the bubble pops with a NOVA
  m.bounces = 0         -- RICOCHETE: wall bounces per shot
  m.bounceHoming = false   -- RICOCHETE++: bounced shots home in
  m.shockRadius = 0     -- CHOQUE: mini-NOVA when the dash ends (0 = off)
  m.shockDamage = 0
  m.shockStart = false  -- CHOQUE++: also when it starts
  Upgrades.apply(self, m)
end

-- Respawn marker on death: where the ship died, shown after markerDelay.
function Player:markDeath()
  self.markerX, self.markerY = self.x, self.y
  self.markerDelay = R.markerDelay
end

-- Respawn marker for the comeback at wave end: the safest spot, right away.
function Player:placeMarker(world)
  self.markerX, self.markerY = world:safeSpot()
  self.markerDelay = 0
end

-- Match start: the ship is placed but hidden while the briefing is up
-- (the game is frozen under it), then beams in with Player:arrive().
function Player:place(x, y)
  self:spawn(x, y, true)
  self.hidden = true
  self.spawnFx = 0
end

function Player:arrive()
  if not self.hidden then return end
  self.hidden = false
  self.spawnFx = P.spawnFxTime
  Audio.play("player_spawn")
end

-- `quiet`: no spawn sound (the match start plays it on arrival).
function Player:spawn(x, y, quiet)
  self.hidden = false
  self.x, self.y = x, y
  self.vx, self.vy = 0, 0
  self.alive = true
  self.invuln = P.invulnTime
  self.respawnTimer = 0
  self.fireCooldown = 0
  self.target = nil
  self.aimX, self.aimY = 0, -1
  self.angle = UP
  self.muzzle = 0
  self.ribbonN = 0          -- no ribbon from the death spot to here
  self.dashT, self.dashSafe, self.dashCd, self.dashBuffer = 0, 0, 0, 0
  self.dashLinger, self.dashLingering, self.dashTouched = 0, false, false
  self.readyFlash, self.ghostN, self.ghostT = 0, 0, 0
  self.spawnFx = P.spawnFxTime
  if not quiet then Audio.play("player_spawn") end
  -- Morrer custa os power-ups temporários.
  require("src.systems.powerups").clear(self)
end

-- ---------------------------------------------------------------------------
-- Auto-aim target: keeps the locked enemy while it lives and stays on screen,
-- unless another one is clearly closer (switchRatio), so the aim does not
-- flicker between two enemies at about the same distance.
-- ---------------------------------------------------------------------------
function Player:autoTarget(world)
  local A = Config.AUTO_AIM
  if not A.enabled then
    self.target = nil
    return nil
  end

  local t, td2 = self.target, nil
  if t then
    if t.dead or not world:isOnScreen(t.x, t.y) then
      t = nil
    else
      td2 = Util.dist2(self.x, self.y, t.x, t.y)
    end
  end

  local best = world:nearestVisibleEnemy(self.x, self.y)
  if not t then
    t = best
  elseif best and best ~= t then
    local ratio2 = A.switchRatio * A.switchRatio
    if Util.dist2(self.x, self.y, best.x, best.y) < td2 * ratio2 then t = best end
  end

  self.target = t
  return t
end

-- ---------------------------------------------------------------------------
-- Aim: right stick > d-pad > auto-aim target > movement direction > last aim.
-- Returns whether the ship should fire: only with manual aim or a target.
-- ---------------------------------------------------------------------------
function Player:updateAim(moveX, moveY, world)
  local d = self.device

  local ax, ay = d:aimVector()
  if ax == 0 and ay == 0 then ax, ay = d:dpadVector() end
  if ax ~= 0 or ay ~= 0 then
    -- Manual aim wins; drop the lock so releasing the stick picks afresh.
    self.target = nil
    self.aimX, self.aimY = Util.normalize(ax, ay)
    return true
  end

  local t = self:autoTarget(world)
  if t then
    local nx, ny, len = Util.normalize(t.x - self.x, t.y - self.y)
    if len > 0 then self.aimX, self.aimY = nx, ny end
    return true
  end

  -- No manual aim and no target: hold fire, face the movement direction
  -- (or keep the last aim while standing still).
  if moveX ~= 0 or moveY ~= 0 then
    self.aimX, self.aimY = Util.normalize(moveX, moveY)
  end
  return false
end

-- Engine ribbon: a new tail point every ribbonEvery s (newest first; the
-- arrays are shifted, they are tiny). Old points age out in drawRibbon.
local function sampleRibbon(self, dt)
  self.ribbonT = self.ribbonT - dt
  if self.ribbonT > 0 then return end
  self.ribbonT = TR.ribbonEvery
  local xs, ys, at = self.ribbonX, self.ribbonY, self.ribbonAt
  local n = math.min(self.ribbonN + 1, TR.ribbonPoints)
  for i = n, 2, -1 do
    xs[i], ys[i], at[i] = xs[i - 1], ys[i - 1], at[i - 1]
  end
  local back = SIZE.playerShip * 0.45
  xs[1] = self.x - math.cos(self.angle) * back
  ys[1] = self.y - math.sin(self.angle) * back
  at[1] = self.ribbonClock
  self.ribbonN = n
end

-- Dash afterimages: a new copy every ghostEvery s during the burst (newest
-- first; the arrays are shifted, they are tiny). They age out in drawGhosts.
local function sampleGhosts(self, dt)
  if self.dashT <= 0 then return end
  self.ghostT = self.ghostT - dt
  if self.ghostT > 0 then return end
  self.ghostT = D.ghostEvery
  local xs, ys, as, at = self.ghostX, self.ghostY, self.ghostA, self.ghostAt
  local n = math.min(self.ghostN + 1, D.ghosts)
  for i = n, 2, -1 do
    xs[i], ys[i], as[i], at[i] = xs[i - 1], ys[i - 1], as[i - 1], at[i - 1]
  end
  xs[1], ys[1], as[1], at[1] = self.x, self.y, self.angle, self.ribbonClock
  self.ghostN = n
end

-- Protected by the dash: during the burst + grace, or while lingering inside
-- an enemy right after it (Combat sets dashTouched to keep that going).
function Player:dashGuarded()
  return self.dashSafe > 0 or self.dashLingering
end

-- Dash timers, the press (buffered) and the burst start. Returns whether the
-- ship is mid-burst this frame (Player:update then moves it at burst speed).
function Player:updateDash(dt, moveX, moveY, world)
  if self.readyFlash > 0 then self.readyFlash = self.readyFlash - dt end
  if self.dashCd > 0 then
    self.dashCd = self.dashCd - dt
    if self.dashCd <= 0 then self.readyFlash = D.readyFlash end
  end
  if self.dashBuffer > 0 then self.dashBuffer = self.dashBuffer - dt end
  local d = self.device
  if d.connected and d:pressed("dash") then self.dashBuffer = D.buffer end

  -- Protection: burst + grace; then, if Combat finds the ship inside an
  -- enemy, it lingers while it keeps touching one (up to lingerMax).
  if self.dashSafe > 0 then
    self.dashSafe = self.dashSafe - dt
    if self.dashSafe <= 0 then self.dashLingering = true end
  elseif self.dashLingering then
    self.dashLinger = self.dashLinger - dt
    if not self.dashTouched or self.dashLinger <= 0 then self.dashLingering = false end
  end
  self.dashTouched = false

  -- Burst over: leave at normal top speed the same way (no skid, no halt).
  if self.dashT > 0 then
    self.dashT = self.dashT - dt
    if self.dashT <= 0 then
      local v = P.speed * self.mods.speedMul
      self.vx, self.vy = self.dashDX * v, self.dashDY * v
      -- CHOQUE: a mini-NOVA where the burst ends.
      local m = self.mods
      if m.shockRadius > 0 then world:shockPulse(self, m.shockRadius, m.shockDamage) end
    end
  end

  if self.dashBuffer > 0 and self.dashCd <= 0 and self.dashT <= 0 then
    -- Along the move stick; standing still, where the ship aims.
    local dx, dy = Util.normalize(moveX, moveY)
    if dx == 0 and dy == 0 then dx, dy = Util.normalize(self.aimX, self.aimY) end
    if dx == 0 and dy == 0 then dx, dy = 0, -1 end
    self.dashDX, self.dashDY = dx, dy
    self.dashT = D.time
    self.dashSafe = D.time + D.grace
    self.dashLinger, self.dashLingering = D.lingerMax, false
    self.dashCdMax = D.cooldown * self.mods.dashCdMul
    self.dashCd = self.dashCdMax
    self.dashBuffer, self.readyFlash = 0, 0
    self.ghostN, self.ghostT = 0, 0
    self.bladeN, self.bladeBoss = 0, false   -- LÂMINA: a fresh cut list
    Audio.play("dash")
    -- CHOQUE++: a mini-NOVA where the burst starts too.
    local m = self.mods
    if m.shockStart then world:shockPulse(self, m.shockRadius, m.shockDamage) end
    if Config.SMOKE then require("src.smoke").bump("dashes") end
  end
  return self.dashT > 0
end

-- LÂMINA: mid-burst, every enemy the ship touches takes the blade damage once
-- per dash (the boss too). A kill counts like a shot of this player's; at
-- the top level it recharges the dash. Module-level callback fed by upvalues.
local BLADE_MAX = 16
local bladeSelf, bladeWorld = nil, nil

local function bladeHit(e)
  local p = bladeSelf
  if e.dead then return end
  local rr = P.radius + e.radius
  if Util.dist2(p.x, p.y, e.x, e.y) > rr * rr then return end
  local hits = p.bladeHits
  for i = 1, p.bladeN do
    if hits[i] == e then return end
  end
  if p.bladeN < BLADE_MAX then
    p.bladeN = p.bladeN + 1
    hits[p.bladeN] = e
  end
  local world = bladeWorld
  world:impact(e.x, e.y, -p.dashDX, -p.dashDY, p.color)
  if e:damage(p.mods.blade) then
    e.dead = true
    world:onEnemyKilled(e, p.index)
    if p.mods.bladeReset then
      p.dashCd, p.readyFlash = 0, D.readyFlash
    end
  else
    Audio.play("enemy_hit")
  end
  if Config.SMOKE then require("src.smoke").bump("blades") end
end

function Player:updateBlade(world)
  if self.mods.blade <= 0 then return end
  bladeSelf, bladeWorld = self, world
  Combat.queryCircle(self.x, self.y, P.radius + Config.ENEMY_SPACING.maxSpace, bladeHit)
  bladeSelf, bladeWorld = nil, nil
  local boss = world.boss
  if not self.bladeBoss and boss:isFighting() then
    local rr = P.radius + boss.radius
    if Util.dist2(self.x, self.y, boss.x, boss.y) <= rr * rr then
      self.bladeBoss = true
      boss:hit(self.mods.blade, self.index, world)
      world:impact(self.x, self.y, -self.dashDX, -self.dashDY, self.color)
    end
  end
end

-- RECARGA: a free BOLHA every `recharge` s spent without one.
function Player:updateRecharge(dt, world)
  local m = self.mods
  if m.recharge <= 0 or m.bubble then return end
  self.rechargeT = self.rechargeT + dt
  if self.rechargeT < m.recharge then return end
  self.rechargeT = 0
  local Powerups = require("src.systems.powerups")
  local def = Powerups.byId("bubble")
  Powerups.give(self, def, world)
  world:ring(self.x, self.y, 26, def.color, 0.35)
  world:floatText(self.x, self.y - 14, def.name, def.color)
  if Config.SMOKE then require("src.smoke").bump("recharges") end
end

function Player:update(dt, world)
  self.ribbonClock = self.ribbonClock + dt
  if self.invuln > 0 then self.invuln = self.invuln - dt end
  if self.muzzle > 0 then self.muzzle = self.muzzle - dt end
  if self.spawnFx > 0 then self.spawnFx = self.spawnFx - dt end

  if not self.alive then
    if self.out then return end
    self.respawnTimer = self.respawnTimer - dt
    self:updateMarker(dt, world)
    if self.respawnTimer <= 0 and world:canRespawn(self) then
      local support = not self.revived
      self.revived = false
      self:spawn(self.markerX, self.markerY)
      if support then world:respawnSupport(self) end
      -- Last life (also when back from `out`): comes back with the BOLHA.
      if R.lastLifeBubble and self.lives == 1 then
        local Powerups = require("src.systems.powerups")
        Powerups.give(self, Powerups.byId("bubble"), world)
      end
    end
    return
  end

  local d = self.device
  local moveX, moveY = 0, 0
  if d.connected then moveX, moveY = d:moveVector() end

  local bursting = self:updateDash(dt, moveX, moveY, world)
  if bursting then
    -- Mid-burst: fixed speed along the dash (the walls below stop it).
    local v = D.distance / D.time
    self.vx, self.vy = self.dashDX * v, self.dashDY * v
  else
    -- Movimento com aceleração alta (resposta imediata, sem patinar).
    local speed = P.speed * self.mods.speedMul
    local targetX, targetY = moveX * speed, moveY * speed
    local step = P.accel * dt
    self.vx = Util.approach(self.vx, targetX, step)
    self.vy = Util.approach(self.vy, targetY, step)
  end

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  -- Paredes da arena.
  local a, r = world.arena, P.radius
  if self.x < a.x + r then self.x, self.vx = a.x + r, 0 end
  if self.x > a.x + a.w - r then self.x, self.vx = a.x + a.w - r, 0 end
  if self.y < a.y + r then self.y, self.vy = a.y + r, 0 end
  if self.y > a.y + a.h - r then self.y, self.vy = a.y + a.h - r, 0 end

  if bursting then self:updateBlade(world) end
  self:updateRecharge(dt, world)

  local wantsFire = self:updateAim(moveX, moveY, world)
  -- Purely visual: the ship turns quickly but not instantly toward the aim.
  self.angle = Util.angleLerp(self.angle, math.atan2(self.aimY, self.aimX),
    math.min(1, P.turnRate * dt))
  self.engineT = self.engineT + dt

  -- Tiro automático.
  if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end
  if wantsFire and self.fireCooldown <= 0 then
    local fn = WEAPONS[self.mods.weapon] or WEAPONS.single
    fn(self, world)
    self.fireCooldown = 1 / (W.fireRate * self.mods.fireRateMul)
    self.muzzle = P.muzzleTime
  end
  self:updateRear(dt, world, wantsFire)

  sampleRibbon(self, dt)
  sampleGhosts(self, dt)
  self:updateDrones(dt, world)
end

-- RETAGUARDA: plain shots straight back from the aim (a fan of rearFan at
-- the top level), at rearRate x the main fire rate, whatever the weapon.
function Player:updateRear(dt, world, wantsFire)
  local m = self.mods
  if self.rearCooldown > 0 then self.rearCooldown = self.rearCooldown - dt end
  if m.rearRate <= 0 or not wantsFire or self.rearCooldown > 0 then return end
  local base = math.atan2(-self.aimY, -self.aimX)
  local n = m.rearFan
  local spread = n > 1 and Config.UPGRADES.rear.fanAngle or 0
  local step = n > 1 and spread / (n - 1) or 0
  local dmg = W.damage * m.damageMul
  for i = 1, n do
    local a = base - spread * 0.5 + step * (i - 1)
    fire(self, world, self.x, self.y, math.cos(a), math.sin(a), W.bulletSpeed, dmg, "single")
  end
  self.rearCooldown = 1 / (W.fireRate * m.fireRateMul * m.rearRate)
end

-- Drones: the DRONE power-up (slot 1 while active, full rate) plus the
-- DRONE FIEL upgrade's (loyalCount of them at loyalRate). They share one
-- orbit, evenly spaced, and each fires on its own at the nearest visible
-- enemy (the auto-aim rule) from where it is.
local MAX_DRONES = 3

local function countDrones(self)
  local m = self.mods
  local n = 0
  if m.drone then n = 1; self.droneRate[1] = 1 end
  for _ = 1, m.loyalCount do
    if n >= MAX_DRONES then break end
    n = n + 1
    self.droneRate[n] = m.loyalRate
  end
  return n
end

function Player:droneXY(i)
  local a = self.droneAngle + (i - 1) / self.droneN * math.pi * 2
  return self.x + math.cos(a) * DR.distance, self.y + math.sin(a) * DR.distance
end

function Player:updateDrones(dt, world)
  local n = countDrones(self)
  self.droneN = n
  if n == 0 then return end
  self.droneAngle = (self.droneAngle + DR.spin * dt) % (math.pi * 2)
  local cd, flash = self.droneCd, self.droneFlash
  for i = 1, n do
    if flash[i] > 0 then flash[i] = flash[i] - dt end
    if cd[i] > 0 then cd[i] = cd[i] - dt end
    local dx, dy = self:droneXY(i)
    local t = world:nearestVisibleEnemy(dx, dy)
    if t then
      local nx, ny, len = Util.normalize(t.x - dx, t.y - dy)
      if len > 0 then
        self.droneAimX[i], self.droneAimY[i] = nx, ny   -- the barrel tracks every frame
        if cd[i] <= 0 then
          flash[i] = DR.flashTime
          fire(self, world, dx + nx * DR.barrel, dy + ny * DR.barrel, nx, ny, W.bulletSpeed,
            DR.damage * self.mods.damageMul, "drone")
          cd[i] = 1 / (DR.fireRate * self.droneRate[i])
          Audio.play("drone_shot")
        end
      end
    end
  end
end

-- Respawn marker: stays where the ship died; after markerDelay the player
-- can steer it with the move stick for the rest of the countdown.
function Player:updateMarker(dt, world)
  if self.markerDelay > 0 then
    self.markerDelay = self.markerDelay - dt
    return
  end
  local d = self.device
  if not d or not d.connected then return end
  local mx, my = d:moveVector()
  if mx == 0 and my == 0 then return end
  local a, m = world.arena, P.radius + 4
  self.markerX = Util.clamp(self.markerX + mx * R.markerSpeed * dt, a.x + m, a.x + a.w - m)
  self.markerY = Util.clamp(self.markerY + my * R.markerSpeed * dt, a.y + m, a.y + a.h - m)
end

-- ---------------------------------------------------------------------------
-- Drawing: everything visual about the player lives here.
-- ---------------------------------------------------------------------------

-- The player ship in `color` (Kenney red swapped by the recolor shader).
-- Shared by the arena, the lobby preview and the HUD lives.
function Player.drawShip(color, x, y, angle, size, alpha)
  Shaders.recolor(color)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  Assets.draw("playerShip", x, y, angle, size)
  Shaders.reset()
end

-- Respawn marker: a pulsing ring in the player's color with its tag, from
-- markerDelay after the death until the ship is back.
local PLAYER_TAGS = { "P1", "P2" }

function Player:drawMarker()
  if self.markerDelay > 0 then return end
  local c = self.color
  local g = love.graphics
  local t = love.timer.getTime()
  local r = SIZE.playerShip * 0.6 + 2 * math.sin(t * 6)
  local alpha = 0.7 + 0.25 * math.sin(t * 6)
  g.setColor(c[1], c[2], c[3], alpha * 0.18)
  g.circle("fill", self.markerX, self.markerY, r)
  g.setColor(c[1], c[2], c[3], alpha)
  g.setLineWidth(2)
  g.circle("line", self.markerX, self.markerY, r)
  g.setLineWidth(1)
  UI.text("body", PLAYER_TAGS[self.index] or "P?", self.markerX - 20, self.markerY - 4, c, 40, "center")
end

-- Engine flame behind the ship while moving (two frames flickering): an
-- outer flame in the player's color with a white core over it, longer the
-- faster the ship goes. Each layer is anchored so its near end stays at the
-- ship's tail while it stretches. The CALLER sets the additive blend: this
-- runs in the arena pass and in the glow layer (scaled by `alphaMul`, with
-- `coreMul` on the white core, which would bloom into a white blob).
local function drawEngine(self, alphaMul, coreMul)
  local speed2 = self.vx * self.vx + self.vy * self.vy
  if speed2 <= P.flameMinSpeed * P.flameMinSpeed then return end
  local g = love.graphics
  local c = self.color
  local E = Config.ART.engine
  local fx, fy = math.cos(self.angle), math.sin(self.angle)
  local frame = math.floor(self.engineT * E.flickerRate) % 2 == 0 and "engineFlame1" or "engineFlame2"
  local t = math.min(1, (math.sqrt(speed2) - P.flameMinSpeed) / (P.speed - P.flameMinSpeed))
  local stretch = E.stretchMin + (E.stretchMax - E.stretchMin) * t
  local back = SIZE.playerShip * 0.5
  local rot = self.angle + math.pi
  local d = back + SIZE.engineFlame * 0.5 * (stretch - 1)
  g.setColor(c[1], c[2], c[3], alphaMul)
  Assets.draw(frame, self.x - fx * d, self.y - fy * d, rot, SIZE.engineFlame, 1, stretch)
  d = back + SIZE.engineCore * 0.5 * (stretch - 1)
  g.setColor(1, 1, 1, E.coreAlpha * alphaMul * coreMul)
  Assets.draw(frame, self.x - fx * d, self.y - fy * d, rot, SIZE.engineCore, 1, stretch)
end

-- Engine ribbon geometry: a triangle strip through the live tail (while
-- alive) and the sampled points younger than ribbonLife, narrowing and
-- fading with age, in the player's color. Built once per frame in
-- Player:draw (into the reused mesh); the glow layer draws the same mesh.
local rpx, rpy, rpa = {}, {}, {}   -- scratch: points and their age (0..1)

local function buildRibbon(self)
  local m = 0
  if self.alive then
    local back = SIZE.playerShip * 0.45
    m = 1
    rpx[1] = self.x - math.cos(self.angle) * back
    rpy[1] = self.y - math.sin(self.angle) * back
    rpa[1] = 0
  end
  for i = 1, self.ribbonN do
    local age = (self.ribbonClock - self.ribbonAt[i]) / TR.ribbonLife
    if age >= 1 then break end
    m = m + 1
    rpx[m], rpy[m], rpa[m] = self.ribbonX[i], self.ribbonY[i], age
  end
  self.ribbonM = m
  if m < 2 then return end
  local mesh, c = self.ribbonMesh, self.color
  for i = 1, m do
    -- Direction along the strip from the neighbors (ends use one side).
    local a, b = math.max(1, i - 1), math.min(m, i + 1)
    local dx, dy = rpx[a] - rpx[b], rpy[a] - rpy[b]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then dx, dy, len = 1, 0, 1 end
    local k = 1 - rpa[i]
    local hw = TR.ribbonWidth * 0.5 * k
    local ox, oy = -dy / len * hw, dx / len * hw
    local alpha = TR.ribbonAlpha * k * k
    mesh:setVertex(i * 2 - 1, rpx[i] + ox, rpy[i] + oy, 0, 0, c[1], c[2], c[3], alpha)
    mesh:setVertex(i * 2, rpx[i] - ox, rpy[i] - oy, 0, 1, c[1], c[2], c[3], alpha)
  end
  mesh:setDrawRange(1, m * 2)
end

-- Draws the ribbon built this frame; additive, the CALLER sets the blend.
local function drawRibbon(self, alphaMul)
  if (self.ribbonM or 0) < 2 then return end
  love.graphics.setColor(1, 1, 1, alphaMul)
  love.graphics.draw(self.ribbonMesh)
end

-- Muzzle flash at the gun (ahead of the ship, along the aim) for
-- PLAYER.muzzleTime after each shot: a halo in the player's color and a hot
-- core, shrinking. Additive, the CALLER sets the blend; `scale` grows it
-- (glow layer).
local function drawMuzzle(self, alphaMul, scale)
  if self.muzzle <= 0 then return end
  local k = self.muzzle / P.muzzleTime
  local d = SIZE.playerShip * MZ.nose
  local x, y = self.x + self.aimX * d, self.y + self.aimY * d
  local c = self.color
  local g = love.graphics
  g.setColor(c[1], c[2], c[3], k * alphaMul)
  g.circle("fill", x, y, MZ.size * scale * (0.6 + 0.4 * k))
  g.setColor(1, 0.97, 0.85, k * alphaMul)
  g.circle("fill", x, y, MZ.coreSize * scale)
end

-- Respawn materialize: 0 = just spawned, 1 = whole (spawnFx is done).
local RESPAWN_DETAILS = 0.7            -- outline/flame/muzzle show from here
local BEAM_EDGE = { 1, 0.95, 0.8 }     -- hot white front of the build

local function spawnProgress(self)
  if self.spawnFx <= 0 then return 1 end
  return 1 - self.spawnFx / P.spawnFxTime
end

-- Teleport beam (Config.FX.beam): a column of light coming down onto the
-- ship while it materializes, a wide faint layer under a thin bright core,
-- fading as the ship completes. Additive, the CALLER sets the blend.
local function drawBeam(self, alphaMul)
  if self.spawnFx <= 0 then return end
  local BM = Config.FX.beam
  local a = math.min(1, (1 - spawnProgress(self)) * 2.5) * BM.alpha * alphaMul
  local c = self.color
  local g = love.graphics
  local cy = self.y - BM.height * 0.5
  g.setColor(c[1], c[2], c[3], a * 0.45)
  g.draw(Assets.white, self.x, cy, 0, BM.width * 1.8, BM.height, 0.5, 0.5)
  g.setColor(c[1] + (1 - c[1]) * 0.6, c[2] + (1 - c[2]) * 0.6, c[3] + (1 - c[3]) * 0.6, a)
  g.draw(Assets.white, self.x, cy, 0, BM.width * 0.45, BM.height, 0.5, 0.5)
end

-- Ship hidden this frame by the invulnerability blink.
-- Not while it materializes: the build must be seen whole.
local function blinkedOff(self)
  if self.spawnFx > 0 then return false end
  return self.invuln > 0 and math.floor(self.invuln * P.blinkRate) % 2 == 0
end

-- Dash afterimages: fading copies of the ship in its color, older = fainter.
-- `glow` (glow layer): a soft disc per copy instead of the sprite.
local function drawGhosts(self, alphaMul, glow)
  local c = self.color
  for i = 1, self.ghostN do
    local age = (self.ribbonClock - self.ghostAt[i]) / D.ghostLife
    if age >= 1 then break end
    local a = D.ghostAlpha * (1 - age) * (1 - 0.5 * (i - 1) / D.ghosts) * alphaMul
    if glow then
      love.graphics.setColor(c[1], c[2], c[3], a)
      love.graphics.circle("fill", self.ghostX[i], self.ghostY[i], SIZE.playerShip * 0.45)
    else
      Player.drawShip(c, self.ghostX[i], self.ghostY[i], self.ghostA[i], SIZE.playerShip, a)
    end
  end
end

-- Dash cooldown: a thin arc around the ship filling clockwise from the top
-- while it recharges, then a full ring flashing outward when it is back.
local function drawDashRing(self, alphaMul)
  local g = love.graphics
  local c = self.color
  local r = SIZE.playerShip * D.ring.radius
  g.setLineWidth(D.ring.width)
  if self.dashCd > 0 then
    local k = 1 - self.dashCd / self.dashCdMax
    g.setColor(c[1], c[2], c[3], D.ring.alpha * alphaMul)
    g.arc("line", "open", self.x, self.y, r, -math.pi / 2, -math.pi / 2 + k * math.pi * 2, 24)
  elseif self.readyFlash > 0 then
    local f = self.readyFlash / D.readyFlash
    g.setColor(c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5, f * alphaMul)
    g.circle("line", self.x, self.y, r + 3 * (1 - f))
  end
  g.setLineWidth(1)
end

-- Shadow layer (src/post.lua): the ship's silhouette, offset down-right.
-- Same visibility as Player:draw (none while dead, blinks with the ship).
function Player:drawShadow()
  if self.hidden or not self.alive or blinkedOff(self) then return end
  if spawnProgress(self) < RESPAWN_DETAILS then return end   -- still materializing
  local dx, dy = Post.shadowOffset(SIZE.playerShip)
  Assets.draw("playerShip", self.x + dx, self.y + dy, self.angle, SIZE.playerShip)
end

-- Glow layer (src/post.lua): engine flame, a faint aura in the player's
-- color, and the shield/bubble/respawn rings. Mirrors Player:draw's
-- visibility rules (marker while dead, blink while invulnerable).
function Player:drawGlow()
  if self.hidden then return end   -- match start, under the briefing
  local g = love.graphics
  local c = self.color
  local EMIT = Config.FX.emit
  drawRibbon(self, EMIT.ribbon)   -- the mesh Player:draw built this frame
  if not self.alive then
    if not self.out and self.markerDelay <= 0 then
      local t = love.timer.getTime()
      g.setColor(c[1], c[2], c[3], EMIT.shield * (0.7 + 0.25 * math.sin(t * 6)))
      g.setLineWidth(2)
      g.circle("line", self.markerX, self.markerY, SIZE.playerShip * 0.6 + 2 * math.sin(t * 6))
      g.setLineWidth(1)
    end
    return
  end
  if self.spawnFx > 0 then
    local t = self.spawnFx / P.spawnFxTime
    g.setColor(c[1], c[2], c[3], t * EMIT.shield)
    g.setLineWidth(2)
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.5 + 20 * t)
    g.setLineWidth(1)
    drawBeam(self, EMIT.shield)
  end
  if self.invuln > 0 then
    g.setColor(c[1], c[2], c[3], EMIT.shield * (0.6 + 0.2 * math.sin(self.invuln * 14)))
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.62)
  end
  drawGhosts(self, EMIT.shield, true)
  if self.readyFlash > 0 then drawDashRing(self, EMIT.shield) end
  if blinkedOff(self) then return end

  g.setColor(c[1], c[2], c[3], EMIT.ship * spawnProgress(self))
  g.circle("fill", self.x, self.y, SIZE.playerShip * 0.55)
  if spawnProgress(self) >= RESPAWN_DETAILS then
    drawEngine(self, EMIT.engine, EMIT.engineCore)
    drawMuzzle(self, EMIT.muzzle, 1.6)
  end

  if self.mods.bubble then
    local bc = BUBBLE_COLOR
    g.setColor(bc[1], bc[2], bc[3], EMIT.shield)
    g.setLineWidth(1.5)
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.72 + math.sin(self.engineT * 5) * 1.2)
    g.setLineWidth(1)
  end
  for i = 1, self.droneN do
    if self.droneFlash[i] > 0 then
      local dx, dy = self:droneXY(i)
      g.setColor(1, 1, 1, 1)
      g.circle("fill", dx + self.droneAimX[i] * DR.barrel, dy + self.droneAimY[i] * DR.barrel, 3)
    end
  end
end

function Player:draw()
  if self.hidden then return end   -- match start, under the briefing (see :place)
  local g = love.graphics
  -- Engine ribbon under everything of the ship (it also fades out after a
  -- death, so it is drawn before the dead early-out).
  buildRibbon(self)
  g.setBlendMode("add")
  drawRibbon(self, 1)
  g.setBlendMode("alpha")

  if not self.alive then
    if not self.out then self:drawMarker() end
    return
  end
  local c = self.color

  -- Respawn ring: a circle in the player's color closing in on the ship.
  if self.spawnFx > 0 then
    local t = self.spawnFx / P.spawnFxTime
    g.setColor(c[1], c[2], c[3], t)
    g.setLineWidth(2)
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.5 + 20 * t)
    g.setLineWidth(1)
  end

  -- Shield bubble while invulnerable; stays solid while the ship blinks so
  -- the player never loses track of where they are.
  if self.invuln > 0 then
    local pulse = 0.35 + 0.2 * math.sin(self.invuln * 14)
    g.setColor(c[1], c[2], c[3], pulse * 0.35)
    g.circle("fill", self.x, self.y, SIZE.playerShip * 0.62)
    g.setColor(c[1], c[2], c[3], pulse + 0.25)
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.62)
  end

  -- Respawn beam over the ship while it materializes.
  g.setBlendMode("add")
  drawBeam(self, 1)
  g.setBlendMode("alpha")

  -- Dash afterimages and cooldown ring: shown through the blink, like the
  -- shield bubble (they tell where the ship went and when it dashes again).
  drawGhosts(self, 1, false)
  drawDashRing(self, 1)

  -- Blink during invulnerability.
  if blinkedOff(self) then return end

  -- Materializing (respawn): the outline, flame and muzzle wait until the
  -- ship is mostly built, so they don't float around nothing.
  local built = spawnProgress(self)
  local whole = built >= RESPAWN_DETAILS

  -- Outline: a lightened, gently pulsing silhouette under the flame and the
  -- ship, so each player finds their own ship in the chaos. Arena only
  -- (drawShip, used by the lobby and HUD, stays clean). Blinks with the ship
  -- (drawn after the invulnerability early-out above).
  -- Under DANO X2 the outline takes the power-up color and pulses faster.
  if whole then
    local O = Config.ART.outline
    local l = O.lighten
    local oc, rate = c, O.pulseRate
    if self.mods.damageMul > 1 then
      local X2 = Config.POWERUPS.damage
      oc, rate = X2.color, X2.auraRate
    end
    g.setColor(oc[1] + (1 - oc[1]) * l, oc[2] + (1 - oc[2]) * l, oc[3] + (1 - oc[3]) * l,
      O.alpha + O.pulseAmp * math.sin(self.engineT * rate * math.pi * 2))
    Assets.draw("playerOutline", self.x, self.y, self.angle, SIZE.playerShip)

    g.setBlendMode("add")
    drawEngine(self, 1, 1)
    g.setBlendMode("alpha")
  end

  if built < 1 then
    -- Built top to bottom (in screen space) with a hot white front, in the
    -- player's color.
    local dx, dy = Shaders.spriteDown("playerShip", self.angle)
    if Shaders.dissolve(built, BEAM_EDGE, true, dx, dy, c) then
      g.setColor(1, 1, 1, 1)
    else
      g.setColor(1, 1, 1, built)
    end
    Assets.draw("playerShip", self.x, self.y, self.angle, SIZE.playerShip)
    Shaders.reset()
  else
    Player.drawShip(c, self.x, self.y, self.angle, SIZE.playerShip)
  end

  if whole then
    g.setBlendMode("add")
    drawMuzzle(self, 1, 1)
    g.setBlendMode("alpha")
  end

  -- BOLHA: a wobbling bubble around the ship while it is active.
  if self.mods.bubble then
    local bc = BUBBLE_COLOR
    local r = SIZE.playerShip * 0.72 + math.sin(self.engineT * 5) * 1.2
    g.setColor(bc[1], bc[2], bc[3], 0.16)
    g.circle("fill", self.x, self.y, r)
    g.setColor(bc[1], bc[2], bc[3], 0.75)
    g.setLineWidth(1.5)
    g.circle("line", self.x, self.y, r)
    g.setLineWidth(1)
  end

  -- Drones orbiting the ship, in the player's color.
  -- The sprite is a plain disc, so a short barrel shows where it aims.
  for i = 1, self.droneN do
    local dx, dy = self:droneXY(i)
    local tx, ty = dx + self.droneAimX[i] * DR.barrel, dy + self.droneAimY[i] * DR.barrel
    g.setColor(c[1], c[2], c[3], 1)
    g.setLineWidth(2)
    g.line(dx, dy, tx, ty)
    g.setLineWidth(1)
    Assets.draw("drone", dx, dy, self.droneAngle * 2, SIZE.drone)
    if self.droneFlash[i] > 0 then
      g.setColor(1, 1, 1, 1)
      g.circle("fill", tx, ty, 2)
    end
  end

  -- Reticle ahead of the ship along the aim; pops a little on each shot.
  local flash = self.muzzle > 0
  local dist = P.reticleDistance
  UI.crosshair(c, self.x + self.aimX * dist, self.y + self.aimY * dist,
    flash and P.reticleSize * 1.25 or P.reticleSize, 0.9)

  g.setColor(1, 1, 1, 1)
end

function Player:drawDebug()
  love.graphics.setColor(1, 0, 0, 0.6)
  love.graphics.circle("line", self.x, self.y, P.radius)
  love.graphics.setColor(1, 1, 1, 1)
end

Player.WEAPONS = WEAPONS
return Player
