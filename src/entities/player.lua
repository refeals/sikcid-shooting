-- Jogador. Não é pooled: existem no máximo 2 instâncias, criadas no início
-- da partida. Lê input SÓ do seu device (self.device).

local Config  = require("src.config")
local Util    = require("src.util")
local Audio   = require("src.audio")
local Assets  = require("src.assets")
local Shaders = require("src.shaders")
local UI      = require("src.ui")

local P = Config.PLAYER
local W = Config.WEAPON
local SIZE = Config.ART.size

local UP = -math.pi / 2

local Player = {}
Player.__index = Player

-- Armas disponíveis, indexadas por mods.weapon. As etapas seguintes só
-- acrescentam entradas aqui; nada de `if` espalhado pelo update.
local WEAPONS = {}

WEAPONS.single = function(self, world)
  world:spawnBullet(self.x, self.y, self.aimX, self.aimY,
    W.bulletSpeed, self.mods.damage, self.index, "single", nil, nil, self.color)
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
    world:spawnBullet(self.x, self.y, math.cos(a), math.sin(a),
      W.bulletSpeed, self.mods.damage, self.index, "spread", nil, nil, self.color)
  end
  Audio.play("shot_spread")
end

-- Missiles: projétil lento que corrige a rota até o inimigo mais próximo.
WEAPONS.missiles = function(self, world)
  world:spawnBullet(self.x, self.y, self.aimX, self.aimY,
    W.missileSpeed, self.mods.damage, self.index, "missile",
    W.bulletLife * 2, W.bulletRadius + 1, self.color)
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
    orbAngle = 0,
    muzzle = 0,               -- clarão curto do cano ao atirar
    spawnFx = 0,              -- anel de respawn
    mods = {},
    powerups = {},            -- { { def = <DEF>, timeLeft = s }, ... }
  }, Player)
  self:resetMods()
  return self
end

-- Valores base da arma/movimento. Os power-ups reaplicam por cima disto.
function Player:resetMods()
  local m = self.mods
  m.speedMul = 1
  m.fireRateMul = 1
  m.damage = W.damage
  m.weapon = "single"
  m.orbs = 0
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
  self.spawnFx = P.spawnFxTime
  Audio.play("player_spawn")
  -- Morrer custa os power-ups temporários.
  require("src.systems.powerups").clear(self)
end

-- ---------------------------------------------------------------------------
-- Auto-aim target: keeps the locked enemy while it lives and stays in range,
-- unless another one is clearly closer (switchRatio), so the aim does not
-- flicker between two enemies at about the same distance.
-- ---------------------------------------------------------------------------
function Player:autoTarget(world)
  local A = Config.AUTO_AIM
  if not A.enabled then
    self.target = nil
    return nil
  end
  local r2 = A.radius * A.radius

  local t, td2 = self.target, nil
  if t then
    td2 = Util.dist2(self.x, self.y, t.x, t.y)
    if t.dead or td2 > r2 then t, td2 = nil, nil end
  end

  local best = world:nearestEnemy(self.x, self.y, A.radius)
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

function Player:update(dt, world)
  if self.invuln > 0 then self.invuln = self.invuln - dt end
  if self.muzzle > 0 then self.muzzle = self.muzzle - dt end
  if self.spawnFx > 0 then self.spawnFx = self.spawnFx - dt end

  if not self.alive then
    if self.out then return end
    self.respawnTimer = self.respawnTimer - dt
    if self.respawnTimer <= 0 and world:canRespawn(self) then
      self:spawn(world.arena.cx, world.arena.cy)
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

  self.orbAngle = (self.orbAngle + W.orbSpeed * dt) % (math.pi * 2)
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

function Player:draw()
  if not self.alive then return end
  local c = self.color
  local g = love.graphics

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
  if self.invuln > 0 and math.floor(self.invuln * P.blinkRate) % 2 == 0 then
    return
  end

  local fx, fy = math.cos(self.angle), math.sin(self.angle)

  -- Outline: a lightened, gently pulsing silhouette under the flame and the
  -- ship, so each player finds their own ship in the chaos. Arena only
  -- (drawShip, used by the lobby and HUD, stays clean). Blinks with the ship
  -- (drawn after the invulnerability early-out above).
  local O = Config.ART.outline
  local l = O.lighten
  g.setColor(c[1] + (1 - c[1]) * l, c[2] + (1 - c[2]) * l, c[3] + (1 - c[3]) * l,
    O.alpha + O.pulseAmp * math.sin(self.engineT * O.pulseRate * math.pi * 2))
  Assets.draw("playerOutline", self.x, self.y, self.angle, SIZE.playerShip)

  -- Engine flame behind the ship while moving (two frames flickering): an
  -- outer flame in the player's color with a white core over it, both
  -- additive and longer the faster the ship goes. Each layer is anchored so
  -- its near end stays at the ship's tail while it stretches.
  local speed2 = self.vx * self.vx + self.vy * self.vy
  if speed2 > P.flameMinSpeed * P.flameMinSpeed then
    local E = Config.ART.engine
    local frame = math.floor(self.engineT * E.flickerRate) % 2 == 0 and "engineFlame1" or "engineFlame2"
    local t = math.min(1, (math.sqrt(speed2) - P.flameMinSpeed) / (P.speed - P.flameMinSpeed))
    local stretch = E.stretchMin + (E.stretchMax - E.stretchMin) * t
    local back = SIZE.playerShip * 0.5
    local rot = self.angle + math.pi
    local d = back + SIZE.engineFlame * 0.5 * (stretch - 1)
    g.setBlendMode("add")
    g.setColor(c[1], c[2], c[3], 1)
    Assets.draw(frame, self.x - fx * d, self.y - fy * d, rot, SIZE.engineFlame, 1, stretch)
    d = back + SIZE.engineCore * 0.5 * (stretch - 1)
    g.setColor(1, 1, 1, E.coreAlpha)
    Assets.draw(frame, self.x - fx * d, self.y - fy * d, rot, SIZE.engineCore, 1, stretch)
    g.setBlendMode("alpha")
  end

  Player.drawShip(c, self.x, self.y, self.angle, SIZE.playerShip)

  -- Orbital Shield orbs (their collision lives in systems/combat.lua).
  local orbs = self.mods.orbs
  if orbs > 0 then
    g.setColor(Config.COLORS.orb)
    for i = 1, orbs do
      local a = self.orbAngle + (i - 1) * (math.pi * 2 / orbs)
      Assets.draw("orb", self.x + math.cos(a) * W.orbDistance, self.y + math.sin(a) * W.orbDistance,
        a * 2, SIZE.orb)
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
