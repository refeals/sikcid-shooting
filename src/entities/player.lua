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
  self.aimX, self.aimY = 0, -1
  self.angle = UP
  self.muzzle = 0
  self.spawnFx = P.spawnFxTime
  Audio.play("player_spawn")
  -- Morrer custa os power-ups temporários.
  require("src.systems.powerups").clear(self)
end

-- ---------------------------------------------------------------------------
-- Mira: analógico direito > d-pad > direção do movimento > última mira válida.
-- Devolve também se o jogador está "mirando de propósito" (para AUTO_FIRE
-- desligado).
-- ---------------------------------------------------------------------------
function Player:updateAim(moveX, moveY)
  local d = self.device
  local aiming = false

  local ax, ay = d:aimVector()
  if ax ~= 0 or ay ~= 0 then
    aiming = true
  else
    ax, ay = d:dpadVector()
    if ax ~= 0 or ay ~= 0 then aiming = true end
  end

  if aiming then
    local nx, ny = Util.normalize(ax, ay)
    self.aimX, self.aimY = nx, ny
  elseif moveX ~= 0 or moveY ~= 0 then
    -- Sem mira explícita: segue o movimento, mas não vira "última mira".
    local nx, ny = Util.normalize(moveX, moveY)
    self.aimX, self.aimY = nx, ny
  end
  -- Caso contrário mantém self.aimX/aimY (última mira válida).

  return aiming
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

  local aiming = self:updateAim(moveX, moveY)
  -- Purely visual: the ship turns quickly but not instantly toward the aim.
  self.angle = Util.angleLerp(self.angle, math.atan2(self.aimY, self.aimX),
    math.min(1, P.turnRate * dt))
  self.engineT = self.engineT + dt

  -- Tiro automático.
  if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end
  local wantsFire = Config.AUTO_FIRE_ALWAYS or aiming
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

  -- Engine flame behind the ship while moving (two frames flickering).
  local speed2 = self.vx * self.vx + self.vy * self.vy
  if speed2 > P.flameMinSpeed * P.flameMinSpeed then
    local frame = math.floor(self.engineT * 20) % 2 == 0 and "engineFlame1" or "engineFlame2"
    local back = SIZE.playerShip * 0.5
    g.setBlendMode("add")
    g.setColor(1, 1, 1, 1)
    Assets.draw(frame, self.x - fx * back, self.y - fy * back, self.angle + math.pi, SIZE.engineFlame)
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
