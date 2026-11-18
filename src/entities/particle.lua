-- Particles. Pooled: only re-initialized, never re-created.
--
-- Two kinds share the pool:
--   "spark" -- small square that shrinks and fades (the original effect);
--   "puff"  -- a Kenney smoke puff tinted with the source color that grows,
--              spins and fades: the body of explosions and missile trails.

local Config = require("src.config")
local Util   = require("src.util")
local Assets = require("src.assets")

local J = Config.JUICE

local PUFFS = { "puff1", "puff2", "puff3", "puff4" }

local Particle = {}
Particle.__index = Particle

function Particle.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0, maxLife = 1,
    size = J.particleSize,
    color = Config.COLORS.flash,
    kind = "spark",
    sprite = PUFFS[1],
    rot = 0, spin = 0,
  }, Particle)
end

function Particle:reset(x, y, dirX, dirY, speed, life, size, color, kind)
  self.x, self.y = x, y
  self.vx, self.vy = dirX * speed, dirY * speed
  self.life = life
  self.maxLife = life
  self.size = size or J.particleSize
  self.color = color or Config.COLORS.flash
  self.kind = kind or "spark"
  if self.kind == "puff" then
    self.sprite = PUFFS[math.random(#PUFFS)]
    self.rot = math.random() * math.pi * 2
    self.spin = Util.randRange(-J.puffSpin, J.puffSpin)
  end
end

-- Scatters `count` sparks from a point (simple burst).
function Particle.burst(pool, count, x, y, color, size)
  for _ = 1, count do
    local p = pool:acquire()
    if not p then return end   -- pool full: drop the rest, never allocate
    local a = math.random() * math.pi * 2
    p:reset(x, y, math.cos(a), math.sin(a),
      Util.randRange(J.particleSpeedMin, J.particleSpeedMax),
      Util.randRange(J.particleLifeMin, J.particleLifeMax),
      size, color)
  end
end

-- Explosion: `puffs` slow smoke puffs of about `puffSize` px, then `sparks`
-- fast sparks. Puffs go first so a nearly full pool still shows the smoke.
function Particle.explosion(pool, x, y, color, puffs, puffSize, sparks, sparkSize)
  for _ = 1, puffs do
    local p = pool:acquire()
    if not p then return end
    local a = math.random() * math.pi * 2
    p:reset(x, y, math.cos(a), math.sin(a),
      Util.randRange(J.puffSpeedMin, J.puffSpeedMax),
      Util.randRange(J.puffLifeMin, J.puffLifeMax),
      puffSize * Util.randRange(0.7, 1.1), color, "puff")
  end
  Particle.burst(pool, sparks, x, y, color, sparkSize)
end

-- One small trail puff left behind a moving object (missiles).
function Particle.trail(pool, x, y, color)
  local p = pool:acquire()
  if not p then return end
  p:reset(x, y, 0, 0, 0, J.trailLife, J.trailSize, color, "puff")
end

function Particle:update(dt)
  self.life = self.life - dt
  if self.life <= 0 then return false end
  -- Simple exponential drag: fast at first, settles at the end.
  local drag = 1 - J.particleDrag * dt
  if drag < 0 then drag = 0 end
  self.vx, self.vy = self.vx * drag, self.vy * drag
  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt
  if self.kind == "puff" then self.rot = self.rot + self.spin * dt end
  return true
end

function Particle:draw()
  local t = self.life / self.maxLife
  local c = self.color
  if self.kind == "puff" then
    -- Grows while fading out.
    love.graphics.setColor(c[1], c[2], c[3], t * J.puffAlpha)
    Assets.draw(self.sprite, self.x, self.y, self.rot, self.size * (1 + (1 - t) * J.puffGrow))
  else
    love.graphics.setColor(c[1], c[2], c[3], t)
    local s = self.size * t
    love.graphics.rectangle("fill", self.x - s * 0.5, self.y - s * 0.5, s, s)
  end
end

return Particle
