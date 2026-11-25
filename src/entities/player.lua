-- Jogador. Não é pooled: existem no máximo 2 instâncias, criadas no início
-- da partida. Lê input SÓ do seu device (self.device).

local Config  = require("src.config")
local Util    = require("src.util")
local Audio   = require("src.audio")
local Assets  = require("src.assets")
local Shaders = require("src.shaders")
local UI      = require("src.ui")
local Post    = require("src.post")

local P = Config.PLAYER
local W = Config.WEAPON
local R = Config.RESPAWN
local DR = Config.POWERUPS.drone
local SIZE = Config.ART.size
local TR = Config.FX.trail
local MZ = Config.FX.muzzle

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
local function fire(self, world, x, y, dx, dy, speed, dmg, kind, life, radius)
  local b = world:spawnBullet(x, y, dx, dy, speed, dmg, self.index, kind, life, radius, self.color)
  if b and self.mods.damageMul > 1 then b.powered = true end
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
    droneAngle = 0,           -- DRONE power-up: orbit angle and fire timer
    droneCooldown = 0,
    droneAimX = 0, droneAimY = -1,   -- barrel direction (last target)
    droneFlash = 0,                  -- muzzle flash on each drone shot
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
  }, Player)
  self:resetMods()
  self.ribbonMesh = love.graphics.newMesh((TR.ribbonPoints + 1) * 2, "strip", "stream")
  return self
end

-- Valores base da arma/movimento. Os power-ups reaplicam por cima disto.
function Player:resetMods()
  local m = self.mods
  m.speedMul = 1
  m.fireRateMul = 1
  m.damage = W.damage
  m.damageMul = 1
  m.weapon = "single"
  m.bubble = false
  m.drone = false
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

function Player:spawn(x, y)
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
  self.spawnFx = P.spawnFxTime
  Audio.play("player_spawn")
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

  -- Movimento com aceleração alta (resposta imediata, sem patinar).
  local speed = P.speed * self.mods.speedMul
  local targetX, targetY = moveX * speed, moveY * speed
  local step = P.accel * dt
  self.vx = Util.approach(self.vx, targetX, step)
  self.vy = Util.approach(self.vy, targetY, step)

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  -- Paredes da arena.
  local a, r = world.arena, P.radius
  if self.x < a.x + r then self.x, self.vx = a.x + r, 0 end
  if self.x > a.x + a.w - r then self.x, self.vx = a.x + a.w - r, 0 end
  if self.y < a.y + r then self.y, self.vy = a.y + r, 0 end
  if self.y > a.y + a.h - r then self.y, self.vy = a.y + a.h - r, 0 end

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

  sampleRibbon(self, dt)
  self:updateDrone(dt, world)
end

-- DRONE power-up: orbits the ship and fires on its own at the nearest
-- visible enemy (same rule as the auto-aim), from where it is.
function Player:droneXY()
  return self.x + math.cos(self.droneAngle) * DR.distance,
         self.y + math.sin(self.droneAngle) * DR.distance
end

function Player:updateDrone(dt, world)
  if not self.mods.drone then return end
  self.droneAngle = (self.droneAngle + DR.spin * dt) % (math.pi * 2)
  if self.droneFlash > 0 then self.droneFlash = self.droneFlash - dt end
  if self.droneCooldown > 0 then self.droneCooldown = self.droneCooldown - dt end
  local dx, dy = self:droneXY()
  local t = world:nearestVisibleEnemy(dx, dy)
  if not t then return end
  local nx, ny, len = Util.normalize(t.x - dx, t.y - dy)
  if len <= 0 then return end
  self.droneAimX, self.droneAimY = nx, ny   -- the barrel tracks every frame
  if self.droneCooldown > 0 then return end
  self.droneFlash = DR.flashTime
  fire(self, world, dx + nx * DR.barrel, dy + ny * DR.barrel, nx, ny, W.bulletSpeed,
    DR.damage * self.mods.damageMul, "drone")
  self.droneCooldown = 1 / DR.fireRate
  Audio.play("drone_shot")
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

-- Ship hidden this frame by the invulnerability blink.
local function blinkedOff(self)
  return self.invuln > 0 and math.floor(self.invuln * P.blinkRate) % 2 == 0
end

-- Shadow layer (src/post.lua): the ship's silhouette, offset down-right.
-- Same visibility as Player:draw (none while dead, blinks with the ship).
function Player:drawShadow()
  if not self.alive or blinkedOff(self) then return end
  local dx, dy = Post.shadowOffset(SIZE.playerShip)
  Assets.draw("playerShip", self.x + dx, self.y + dy, self.angle, SIZE.playerShip)
end

-- Glow layer (src/post.lua): engine flame, a faint aura in the player's
-- color, and the shield/bubble/respawn rings. Mirrors Player:draw's
-- visibility rules (marker while dead, blink while invulnerable).
function Player:drawGlow()
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
  end
  if self.invuln > 0 then
    g.setColor(c[1], c[2], c[3], EMIT.shield * (0.6 + 0.2 * math.sin(self.invuln * 14)))
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.62)
  end
  if blinkedOff(self) then return end

  g.setColor(c[1], c[2], c[3], EMIT.ship)
  g.circle("fill", self.x, self.y, SIZE.playerShip * 0.55)
  drawEngine(self, EMIT.engine, EMIT.engineCore)
  drawMuzzle(self, EMIT.muzzle, 1.6)

  if self.mods.bubble then
    local bc = BUBBLE_COLOR
    g.setColor(bc[1], bc[2], bc[3], EMIT.shield)
    g.setLineWidth(1.5)
    g.circle("line", self.x, self.y, SIZE.playerShip * 0.72 + math.sin(self.engineT * 5) * 1.2)
    g.setLineWidth(1)
  end
  if self.mods.drone and self.droneFlash > 0 then
    local dx, dy = self:droneXY()
    g.setColor(1, 1, 1, 1)
    g.circle("fill", dx + self.droneAimX * DR.barrel, dy + self.droneAimY * DR.barrel, 3)
  end
end

function Player:draw()
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

  -- Blink during invulnerability.
  if blinkedOff(self) then return end

  -- Outline: a lightened, gently pulsing silhouette under the flame and the
  -- ship, so each player finds their own ship in the chaos. Arena only
  -- (drawShip, used by the lobby and HUD, stays clean). Blinks with the ship
  -- (drawn after the invulnerability early-out above).
  -- Under DANO X2 the outline takes the power-up color and pulses faster.
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

  Player.drawShip(c, self.x, self.y, self.angle, SIZE.playerShip)

  g.setBlendMode("add")
  drawMuzzle(self, 1, 1)
  g.setBlendMode("alpha")

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

  -- DRONE orbiting the ship, in the player's color.
  -- The sprite is a plain disc, so a short barrel shows where it aims.
  if self.mods.drone then
    local dx, dy = self:droneXY()
    local tx, ty = dx + self.droneAimX * DR.barrel, dy + self.droneAimY * DR.barrel
    g.setColor(c[1], c[2], c[3], 1)
    g.setLineWidth(2)
    g.line(dx, dy, tx, ty)
    g.setLineWidth(1)
    Assets.draw("drone", dx, dy, self.droneAngle * 2, SIZE.drone)
    if self.droneFlash > 0 then
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
