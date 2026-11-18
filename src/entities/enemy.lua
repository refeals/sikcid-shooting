-- Inimigos. Um único tipo de objeto no pool; o comportamento vem de
-- BEHAVIORS[type], indexado por dados de Config.ENEMIES.
--
-- Manter todos os tipos num pool só evita 4 pools quase vazios e mantém a
-- colisão num loop linear.

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")
local Assets = require("src.assets")
local UI     = require("src.ui")

local SIZE = Config.ART.size
local TURN_RATE = Config.ART.enemyTurnRate
local TANK_SPIN = Config.ART.tankSpin

local Enemy = {}
Enemy.__index = Enemy

local BEHAVIORS = {}

function Enemy.new()
  return setmetatable({
    type = "grunt",
    def = Config.ENEMIES.grunt,
    x = 0, y = 0, vx = 0, vy = 0,
    hp = 1,
    flash = 0,          -- tempo restante de flash branco ao levar dano
    target = nil,       -- jogador perseguido
    retarget = 0,
    fireTimer = 0,
    wobble = 0,
    orbHit = 0,         -- cooldown de dano por orbe (power-up Shield)
    angle = 0,          -- drawn facing (visual only)
  }, Enemy)
end

function Enemy:reset(kind, x, y)
  local def = Config.ENEMIES[kind] or Config.ENEMIES.grunt
  self.type = kind
  self.def = def
  self.x, self.y = x, y
  self.vx, self.vy = 0, 0
  self.hp = def.hp
  self.flash = 0
  self.target = nil
  self.retarget = 0
  self.fireTimer = def.fireInterval and Util.randRange(0.3, def.fireInterval) or 0
  self.wobble = 0
  self.orbHit = 0
  self.radius = def.radius
  self.color = Config.COLORS[def.color]
  self.angle = math.random() * math.pi * 2
end

-- Escolhe (ou troca) o jogador perseguido.
local function pickTarget(self, world)
  self.target = world:nearestPlayer(self.x, self.y)
end

-- ---------------------------------------------------------------------------
-- Comportamentos
-- ---------------------------------------------------------------------------

-- Grunt: linha reta até o jogador mais próximo.
BEHAVIORS.grunt = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  self.vx, self.vy = nx * self.def.speed, ny * self.def.speed
end

-- Runner: rápido e errático; troca de alvo de tempos em tempos e oscila a
-- direção para não andar em linha reta.
BEHAVIORS.runner = function(self, dt, world)
  self.retarget = self.retarget - dt
  if self.retarget <= 0 or not self.target or not self.target.alive then
    self.target = world:randomPlayer() or world:nearestPlayer(self.x, self.y)
    self.retarget = Util.randRange(self.def.retargetMin, self.def.retargetMax)
  end
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end

  self.wobble = self.wobble + dt * 6
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  local a = math.atan2(ny, nx) + math.sin(self.wobble) * self.def.wobble
  self.vx, self.vy = math.cos(a) * self.def.speed, math.sin(a) * self.def.speed
end

-- Tank: lento e reto. O empurrão nos outros inimigos vem da separação
-- (massa maior), não de um caso especial aqui.
BEHAVIORS.tank = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  self.vx, self.vy = nx * self.def.speed, ny * self.def.speed
end

-- Shooter: mantém ~120px de distância e atira projéteis lentos.
BEHAVIORS.shooter = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end

  local dx, dy = t.x - self.x, t.y - self.y
  local nx, ny, dist = Util.normalize(dx, dy)
  local keep = self.def.keepDistance
  local dir = 0
  if dist > keep + 20 then dir = 1 elseif dist < keep - 20 then dir = -1 end
  -- Anda em direção ao alvo (ou para longe) com um passo lateral, para não
  -- ficar parado quando já está na distância certa.
  local sx, sy = -ny, nx
  self.vx = (nx * dir + sx * 0.5) * self.def.speed
  self.vy = (ny * dir + sy * 0.5) * self.def.speed

  self.fireTimer = self.fireTimer - dt
  if self.fireTimer <= 0 then
    self.fireTimer = self.def.fireInterval
    world:spawnBullet(self.x, self.y, nx, ny, self.def.bulletSpeed, 1,
      "enemy", "enemy", self.def.bulletLife)
    Audio.play("shot_enemy")
  end
end

-- ---------------------------------------------------------------------------
function Enemy:update(dt, world)
  if self.flash > 0 then self.flash = self.flash - dt end
  if self.orbHit > 0 then self.orbHit = self.orbHit - dt end

  local behavior = BEHAVIORS[self.type] or BEHAVIORS.grunt
  behavior(self, dt, world)

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  -- Paredes: inimigo não sai da arena (mas pode nascer em cima da porta).
  local a, r = world.arena, self.radius
  if self.x < a.x + r then self.x = a.x + r end
  if self.x > a.x + a.w - r then self.x = a.x + a.w - r end
  if self.y < a.y + r then self.y = a.y + r end
  if self.y > a.y + a.h - r then self.y = a.y + a.h - r end

  -- Visual heading: the tank spins in place, the shooter faces its target
  -- (it strafes, so its velocity would hide where it shoots), the rest face
  -- where they move.
  if self.type == "tank" then
    self.angle = self.angle + TANK_SPIN * dt
  else
    local want
    local t = self.target
    if self.type == "shooter" and t then
      want = math.atan2(t.y - self.y, t.x - self.x)
    elseif self.vx ~= 0 or self.vy ~= 0 then
      want = math.atan2(self.vy, self.vx)
    end
    if want then self.angle = Util.angleLerp(self.angle, want, math.min(1, TURN_RATE * dt)) end
  end

  return true
end

-- Aplica dano; devolve true se morreu agora.
function Enemy:damage(amount)
  self.hp = self.hp - amount
  self.flash = Config.ENEMY_FLASH_TIME
  return self.hp <= 0
end

-- Empurrão (separação entre inimigos, knockback de bala).
function Enemy:push(dx, dy)
  self.x = self.x + dx
  self.y = self.y + dy
end

-- All enemy drawing lives here. The simpleSpace sprites are white, so the
-- type color is just the draw tint; the hit flash draws them untinted.
function Enemy:draw()
  local size = SIZE[self.type] or SIZE.grunt
  if self.flash > 0 then
    love.graphics.setColor(Config.COLORS.flash)
  else
    love.graphics.setColor(self.color)
  end
  Assets.draw(self.type, self.x, self.y, self.angle, size)

  -- Tank HP bar, only once it has taken damage.
  if self.type == "tank" and self.hp < self.def.hp then
    local w = size * 0.7
    UI.bar(self.color, self.x - w * 0.5, self.y + size * 0.5 + 1, w, self.hp / self.def.hp, 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

Enemy.BEHAVIORS = BEHAVIORS
return Enemy
