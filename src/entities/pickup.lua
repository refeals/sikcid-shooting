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

-- Devolve false quando expira (o pool recolhe). `frozen` = respiro entre
-- waves: o pickup continua flutuando, mas o tempo de vida não corre.
function Pickup:update(dt, frozen)
  if not frozen then self.life = self.life - dt end
  self.bob = self.bob + dt * 4
  return self.life > 0 and not self.dead
end

-- Ícone do power-up centrado em (x, y). Usado pelo pickup no chão e pela
-- tela de briefing, para os dois mostrarem exatamente a mesma coisa.
-- Trocar por sprite: só aqui.
function Pickup.drawIcon(def, x, y, s)
  local h = s * 0.5
  love.graphics.setColor(def.color)
  love.graphics.rectangle("fill", x - h, y - h, s, s)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x - h + 2, y - h + 2, s - 4, s - 4)

  -- Letra identificando o power-up (placeholder do futuro sprite).
  love.graphics.setColor(def.color)
  love.graphics.printf(def.letter, x - 20, y - 7, 40, "center")
  love.graphics.setColor(1, 1, 1, 1)
end

function Pickup:draw()
  -- Pisca nos últimos segundos avisando que vai sumir.
  if self.life < PU.blinkAt and math.floor(self.life * 8) % 2 == 0 then return end
  -- Flutua de leve.
  Pickup.drawIcon(self.def, self.x, self.y + math.sin(self.bob) * 2, PU.pickupSize)
end

return Pickup
