-- Projétil. Vive em pool: nunca é criado nem descartado durante a partida,
-- só reinicializado por :reset().

local Config = require("src.config")
local Util   = require("src.util")
local Assets = require("src.assets")

local SIZE = Config.ART.size

local Bullet = {}
Bullet.__index = Bullet

-- Objeto vazio para o pool (campos criados uma única vez).
function Bullet.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0,
    dmg = 1,
    owner = 0,          -- 1 ou 2 = jogador; "enemy" = inimigo
    kind = "single",    -- "single" | "spread" | "missile" | "enemy"
    radius = Config.WEAPON.bulletRadius,
    angle = 0,
    trailT = 0,         -- missile smoke trail countdown
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
end

-- Devolve false quando a bala deve ser recolhida pelo pool.
function Bullet:update(dt, world)
  local arena = world.arena
  self.life = self.life - dt
  if self.life <= 0 then return false end

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
  elseif self.kind == "missile" then
    love.graphics.setColor(1, 1, 1, 1)
    Assets.draw("missile", self.x, self.y, self.angle, SIZE.missile)
  else
    love.graphics.setColor(1, 1, 1, 1)
    Assets.draw("shot", self.x, self.y, self.angle, SIZE.shot)
  end
end

-- Soft glow in the owner's color under player shots, so they read against
-- the dark arena. Drawn in its own pass with additive blending (Game:draw)
-- so the blend mode is switched once, not per bullet.
function Bullet:drawGlow()
  local c = self.color
  local r = self.kind == "missile" and SIZE.missile * 0.35 or SIZE.shot * 0.45
  love.graphics.setColor(c[1], c[2], c[3], 0.45)
  love.graphics.circle("fill", self.x, self.y, r)
end

return Bullet
