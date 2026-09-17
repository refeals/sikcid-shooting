-- Power-up caído no chão. Pooled.

local Config = require("src.config")

local PU = Config.POWERUP

local Pickup = {}
Pickup.__index = Pickup

function Pickup.new()
  return setmetatable({
    x = 0, y = 0,
    def = nil,
    life = 0,
    bob = 0,
    dead = false,
  }, Pickup)
end

function Pickup:reset(x, y, def)
  self.x, self.y = x, y
  self.def = def
  self.life = PU.pickupLife
  self.bob = math.random() * math.pi * 2
  self.dead = false
end

-- Devolve false quando expira (o pool recolhe).
function Pickup:update(dt)
  self.life = self.life - dt
  self.bob = self.bob + dt * 4
  return self.life > 0 and not self.dead
end

-- Todo o desenho do pickup mora aqui.
function Pickup:draw()
  -- Pisca nos últimos segundos avisando que vai sumir.
  if self.life < PU.blinkAt and math.floor(self.life * 8) % 2 == 0 then return end

  local s = PU.pickupSize
  local h = s * 0.5
  local y = self.y + math.sin(self.bob) * 2   -- flutua de leve

  love.graphics.setColor(self.def.color)
  love.graphics.rectangle("fill", self.x - h, y - h, s, s)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", self.x - h + 2, y - h + 2, s - 4, s - 4)

  -- Letra identificando o power-up (placeholder do futuro sprite).
  love.graphics.setColor(self.def.color)
  love.graphics.printf(self.def.letter, self.x - 20, y - 7, 40, "center")
  love.graphics.setColor(1, 1, 1, 1)
end

return Pickup
