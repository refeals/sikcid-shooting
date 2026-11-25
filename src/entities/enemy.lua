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
local Combat = require("src.systems.combat")

local SIZE = Config.ART.size
local TURN_RATE = Config.ART.enemyTurnRate
local TANK_SPIN = Config.ART.tankSpin
local SP = Config.ENEMY_SPACING
local WD = Config.ENEMY_WANDER

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
    dead = false,       -- flagged on death, swept by Combat at the end of the frame
    angle = 0,          -- drawn facing (visual only)
    space = 10,         -- half the drawn size: spacing between enemies
    wandering = false,  -- no live player: roaming (see wander)
    heading = 0,
    wantHeading = 0,
    wanderTimer = 0,
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
  self.dead = false
  self.radius = def.radius
  self.color = Config.COLORS[def.color]
  self.angle = math.random() * math.pi * 2
  self.space = (SIZE[kind] or def.size) * 0.5
  self.wandering = false
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
-- No live player: roam instead of freezing. Starts along the current
-- heading, picks a new one every few seconds (pointing back inside near the
-- walls) and eases into it, at a reduced speed.
-- ---------------------------------------------------------------------------
local function wander(self, dt, world)
  if not self.wandering then
    self.wandering = true
    self.target = nil
    if self.vx ~= 0 or self.vy ~= 0 then
      self.heading = math.atan2(self.vy, self.vx)
    else
      self.heading = self.angle
    end
    self.wantHeading = self.heading
    self.wanderTimer = Util.randRange(WD.turnMin, WD.turnMax)
  end

  self.wanderTimer = self.wanderTimer - dt
  if self.wanderTimer <= 0 then
    self.wanderTimer = Util.randRange(WD.turnMin, WD.turnMax)
    local a, m = world.arena, WD.wallMargin
    if self.x < a.x + m or self.x > a.x + a.w - m or self.y < a.y + m or self.y > a.y + a.h - m then
      self.wantHeading = math.atan2(a.cy - self.y, a.cx - self.x)
        + Util.randRange(-WD.inwardSpread, WD.inwardSpread)
    else
      self.wantHeading = self.heading + Util.randRange(-WD.maxTurn, WD.maxTurn)
    end
  end

  self.heading = Util.turnToward(self.heading, self.wantHeading, WD.turnRate * dt)
  local speed = self.def.speed * WD.speedMul
  self.vx, self.vy = math.cos(self.heading) * speed, math.sin(self.heading) * speed
end

-- ---------------------------------------------------------------------------
-- Avoidance: bends the velocity away from neighbors closer than their two
-- spaces plus the gap (stronger the closer they are), keeping the speed.
-- The query callback is a module-level function fed by upvalues, so no
-- closure is created per enemy per frame.
-- ---------------------------------------------------------------------------
local avSelf, avX, avY = nil, 0, 0

local function avoidNeighbor(other)
  if other == avSelf or other.dead then return end
  local want = avSelf.space + other.space + SP.gap
  local dx, dy = avSelf.x - other.x, avSelf.y - other.y
  local d2 = dx * dx + dy * dy
  if d2 >= want * want then return end
  if d2 <= 0.0001 then
    -- Same spot (fresh batch at a door): the overlap fix splits them.
    return
  end
  local d = math.sqrt(d2)
  local k = (1 - d / want) / d
  avX, avY = avX + dx * k, avY + dy * k
end

local function avoid(self, world)
  local vx, vy = self.vx, self.vy
  if vx == 0 and vy == 0 then return end
  avSelf, avX, avY = self, 0, 0
  Combat.queryCircle(self.x, self.y, self.space + SP.maxSpace + SP.gap, avoidNeighbor)

  local boss = world.boss
  if boss and (boss.state == "enter" or boss.state == "fight") then
    local want = self.space + boss.size * SP.bossFrac + SP.gap
    local dx, dy = self.x - boss.x, self.y - boss.y
    local d2 = dx * dx + dy * dy
    if d2 < want * want and d2 > 0.0001 then
      local d = math.sqrt(d2)
      local k = (1 - d / want) / d
      avX, avY = avX + dx * k, avY + dy * k
    end
  end
  avSelf = nil

  if avX == 0 and avY == 0 then return end
  local nx, ny, speed = Util.normalize(vx, vy)
  local fx, fy = Util.normalize(nx + avX * SP.steer, ny + avY * SP.steer)
  if fx == 0 and fy == 0 then return end
  self.vx, self.vy = fx * speed, fy * speed
end

-- ---------------------------------------------------------------------------
function Enemy:update(dt, world)
  if self.flash > 0 then self.flash = self.flash - dt end

  if world:nearestPlayer(self.x, self.y) then
    self.wandering = false
    local behavior = BEHAVIORS[self.type] or BEHAVIORS.grunt
    behavior(self, dt, world)
  else
    wander(self, dt, world)
  end
  avoid(self, world)

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

-- Glow layer (src/post.lua): the white hit flash blooms a little.
function Enemy:drawGlow()
  if self.flash <= 0 then return end
  love.graphics.setColor(1, 1, 1, Config.FX.emit.hitFlash)
  Assets.draw(self.type, self.x, self.y, self.angle, SIZE[self.type] or SIZE.grunt)
end

Enemy.BEHAVIORS = BEHAVIORS
return Enemy
