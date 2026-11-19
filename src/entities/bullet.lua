-- Projétil. Vive em pool: nunca é criado nem descartado durante a partida,
-- só reinicializado por :reset().

local Config  = require("src.config")
local Util    = require("src.util")
local Assets  = require("src.assets")
local Audio   = require("src.audio")
local Shaders = require("src.shaders")

local SIZE = Config.ART.size
local BM = Config.BOSS.missile
local SV = Config.RESPAWN.salvo
local X2 = Config.POWERUPS.damage

local Bullet = {}
Bullet.__index = Bullet

-- Objeto vazio para o pool (campos criados uma única vez).
function Bullet.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0,
    dmg = 1,
    owner = 0,          -- 1 ou 2 = jogador; "enemy" = inimigo
    kind = "single",    -- "single" | "spread" | "missile" | "enemy" | "bossMissile"
    radius = Config.WEAPON.bulletRadius,
    angle = 0,
    trailT = 0,         -- missile smoke trail countdown
    hp = 1,             -- boss missile: hits left before it is shot down
    age = 0,            -- boss missile: seconds since launch
    target = nil,       -- boss missile: player it chases
    powered = false,    -- player shot under DANO X2: drawn bigger and hotter
    dead = false,       -- marcada em combat.lua, recolhida no sweep
    color = Config.COLORS.bullet,
  }, Bullet)
end

function Bullet:reset(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  self.x, self.y = x, y
  self.vx, self.vy = dirX * speed, dirY * speed
  self.speed = speed
  self.life = life or Config.WEAPON.bulletLife
  self.dmg = dmg or 1
  self.owner = owner
  self.kind = kind or "single"
  self.radius = radius or Config.WEAPON.bulletRadius
  self.angle = math.atan2(dirY, dirX)
  self.dead = false
  self.color = color or (owner == "enemy" and Config.COLORS.bulletEnemy or Config.COLORS.bullet)
  self.trailT = 0
  self.hp = 1
  self.age = 0
  self.target = nil
  self.powered = false
end

-- Boss missile going off: when it burns out or is shot down. Visual only.
function Bullet:blast(world)
  world:explosion(self.x, self.y, self.color, 3, SIZE.bossMissile * 0.8, 6, 3)
  Audio.play("missile_fail")
end

-- Boss missile: chases its target for homingTime, then sputters (loses
-- speed, wobbles, smokes harder) for failTime and blows up.
local function updateBossMissile(self, dt, world)
  self.age = self.age + dt
  local speed = BM.speed
  local trailEvery = Config.JUICE.trailInterval
  if self.age < BM.homingTime then
    local t = self.target
    if not t or not t.alive then
      t = world:nearestPlayer(self.x, self.y)
      self.target = t
    end
    if t then
      local want = math.atan2(t.y - self.y, t.x - self.x)
      self.angle = Util.turnToward(self.angle, want, BM.turn * dt)
    end
  else
    local k = math.min(1, (self.age - BM.homingTime) / BM.failTime)
    speed = BM.speed * (1 - (1 - BM.failSpeedMul) * k)
    self.angle = self.angle + math.sin(self.age * 37) * 3 * dt
    trailEvery = trailEvery * 0.5
  end
  self.vx = math.cos(self.angle) * speed
  self.vy = math.sin(self.angle) * speed

  self.trailT = self.trailT - dt
  if self.trailT <= 0 then
    self.trailT = trailEvery
    local back = SIZE.bossMissile * 0.5
    world:trail(self.x - math.cos(self.angle) * back, self.y - math.sin(self.angle) * back, self.color)
  end
end

-- Respawn salvo missile: fired out in a ring, then turns hard toward its own
-- target; if that one dies, the nearest enemy left. Smokes like a missile.
local function updateSalvo(self, dt, world)
  local t = self.target
  if not t or t.dead then
    t = world:nearestEnemy(self.x, self.y, 400)
    self.target = t
  end
  if t then
    local want = math.atan2(t.y - self.y, t.x - self.x)
    self.angle = Util.turnToward(self.angle, want, SV.turn * dt)
    self.vx = math.cos(self.angle) * SV.speed
    self.vy = math.sin(self.angle) * SV.speed
  end
  self.trailT = self.trailT - dt
  if self.trailT <= 0 then
    self.trailT = Config.JUICE.trailInterval
    local back = SIZE.salvo * 0.5
    world:trail(self.x - math.cos(self.angle) * back, self.y - math.sin(self.angle) * back, self.color)
  end
end

-- Devolve false quando a bala deve ser recolhida pelo pool.
function Bullet:update(dt, world)
  local arena = world.arena
  self.life = self.life - dt
  if self.life <= 0 then
    if self.kind == "bossMissile" then self:blast(world) end
    if self.kind == "salvo" then world:salvoBlast(self) end
    return false
  end

  if self.kind == "bossMissile" then updateBossMissile(self, dt, world)
  elseif self.kind == "salvo" then updateSalvo(self, dt, world) end

  -- Míssil: corrige a rota de leve na direção do inimigo mais próximo.
  if self.kind == "missile" then
    local target = world:nearestEnemy(self.x, self.y, 160)
    if target then
      local want = math.atan2(target.y - self.y, target.x - self.x)
      self.angle = Util.turnToward(self.angle, want, Config.WEAPON.missileTurn * dt)
      self.vx = math.cos(self.angle) * self.speed
      self.vy = math.sin(self.angle) * self.speed
    end
    -- Smoke trail from the missile's tail.
    self.trailT = self.trailT - dt
    if self.trailT <= 0 then
      self.trailT = Config.JUICE.trailInterval
      local back = SIZE.missile * 0.5
      world:trail(self.x - math.cos(self.angle) * back, self.y - math.sin(self.angle) * back, self.color)
    end
  end

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  local r = self.radius
  if self.x < arena.x - r or self.x > arena.x + arena.w + r
    or self.y < arena.y - r or self.y > arena.y + arena.h + r then
    return false
  end
  return true
end

-- All bullet drawing lives here. Player bullets are Kenney missiles whose red
-- becomes the owner's color: the CALLER turns the recolor shader on once per
-- owner (see Game:draw) instead of switching it per bullet.
function Bullet:draw()
  if self.kind == "enemy" then
    love.graphics.setColor(self.color)
    Assets.draw("enemyShot", self.x, self.y, self.life * Config.ART.enemyShotSpin, SIZE.enemyShot)
  elseif self.kind == "bossMissile" then
    -- Enemy-shot pink. Once it starts failing it flickers and shakes.
    local x, y, a = self.x, self.y, 1
    if self.age >= BM.homingTime then
      if math.floor(self.age * 18) % 2 == 0 then a = 0.4 end
      x, y = x + Util.randRange(-1, 1), y + Util.randRange(-1, 1)
    end
    Shaders.recolor(self.color)
    love.graphics.setColor(1, 1, 1, a)
    Assets.draw("missile", x, y, self.angle, SIZE.bossMissile)
    Shaders.reset()
  else
    -- Player shots (DANO X2 makes them bigger).
    local k = self.powered and X2.shotScale or 1
    love.graphics.setColor(1, 1, 1, 1)
    if self.kind == "missile" then
      Assets.draw("missile", self.x, self.y, self.angle, SIZE.missile * k)
    elseif self.kind == "salvo" then
      Assets.draw("missile", self.x, self.y, self.angle, SIZE.salvo)
    else
      Assets.draw("shot", self.x, self.y, self.angle, SIZE.shot * k)
    end
  end
end

-- Soft glow in the owner's color under player shots, so they read against
-- the dark arena. Drawn in its own pass with additive blending (Game:draw)
-- so the blend mode is switched once, not per bullet.
function Bullet:drawGlow()
  local c = self.color
  local r = (self.kind == "missile" and SIZE.missile * 0.35)
    or (self.kind == "salvo" and SIZE.salvo * 0.45)
    or SIZE.shot * 0.45
  local a = 0.45
  -- DANO X2: a bigger, stronger glow in the power-up color.
  if self.powered then
    c = X2.color
    r = r * X2.shotScale * X2.glowMul
    a = math.min(1, a * X2.glowMul)
  end
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", self.x, self.y, r)
end

return Bullet
