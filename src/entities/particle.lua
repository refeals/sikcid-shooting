-- Partícula quadrada. Pooled: só reinicializada, nunca recriada.

local Config = require("src.config")
local Util   = require("src.util")

local J = Config.JUICE

local Particle = {}
Particle.__index = Particle

function Particle.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0, maxLife = 1,
    size = J.particleSize,
    color = Config.COLORS.flash,
  }, Particle)
end

function Particle:reset(x, y, dirX, dirY, speed, life, size, color)
  self.x, self.y = x, y
  self.vx, self.vy = dirX * speed, dirY * speed
  self.life = life
  self.maxLife = life
  self.size = size or J.particleSize
  self.color = color or Config.COLORS.flash
end

-- Espalha `count` partículas a partir de um ponto (explosão simples).
function Particle.burst(pool, count, x, y, color, size)
  for _ = 1, count do
    local p = pool:acquire()
    if not p then return end   -- pool cheio: descarta o excedente, sem alocar
    local a = math.random() * math.pi * 2
    p:reset(x, y, math.cos(a), math.sin(a),
      Util.randRange(J.particleSpeedMin, J.particleSpeedMax),
      Util.randRange(J.particleLifeMin, J.particleLifeMax),
      size, color)
  end
end

function Particle:update(dt)
  self.life = self.life - dt
  if self.life <= 0 then return false end
  -- Arrasto exponencial simples: rápido no começo, some no fim.
  local drag = 1 - J.particleDrag * dt
  if drag < 0 then drag = 0 end
  self.vx, self.vy = self.vx * drag, self.vy * drag
  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt
  return true
end

function Particle:draw()
  local t = self.life / self.maxLife
  local c = self.color
  love.graphics.setColor(c[1], c[2], c[3], t)
  local s = self.size * t
  love.graphics.rectangle("fill", self.x - s * 0.5, self.y - s * 0.5, s, s)
end

return Particle
