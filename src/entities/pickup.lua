-- Power-up caído no chão. Pooled.

local Config = require("src.config")
local Assets = require("src.assets")
local UI     = require("src.ui")
local Post   = require("src.post")

local PU = Config.POWERUP
local EMIT = Config.FX.emit

local Pickup = {}
Pickup.__index = Pickup

function Pickup.new()
  return setmetatable({
    x = 0, y = 0,
    def = nil,
    life = 0,
    bob = 0,
    dead = false,
    frozen = false,     -- wave breather: life is paused, so no blinking
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
  self.frozen = frozen and true or false
  if not frozen then self.life = self.life - dt end
  self.bob = self.bob + dt * 4
  return self.life > 0 and not self.dead
end

-- Power-up icon centered at (x, y), `s` px wide: a UIPack badge in the
-- power-up color with its letter (or the plus icon for extra life). Shared by
-- the pickup on the ground, the briefing and the HUD so all three match.
local INK = { 0.08, 0.08, 0.12, 1 }

function Pickup.drawIcon(def, x, y, s, alpha)
  alpha = alpha or 1
  UI.badge(def.color, x, y, s, alpha)
  if def.id == "life" then
    love.graphics.setColor(INK[1], INK[2], INK[3], alpha)
    Assets.draw("iconPlus", x, y, 0, s * 0.55)
  else
    local font = Assets.font("titleSmall")
    love.graphics.setFont(font)
    love.graphics.setColor(INK[1], INK[2], INK[3], alpha)
    -- Pixel font: snap to whole px so the glyphs stay crisp.
    love.graphics.print(def.letter, math.floor(x - font:getWidth(def.letter) * 0.5 + 0.5),
      math.floor(y - font:getHeight() * 0.5 + 1))
    love.graphics.setFont(Assets.font("body"))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Pickup:draw()
  if self:blinkedOff() then return end
  -- Gentle float; the halo is in :drawGlow.
  Pickup.drawIcon(self.def, self.x, self.y + math.sin(self.bob) * 2, Config.ART.size.pickup)
end

-- Blinks in its last seconds as a warning it is about to vanish. Not while
-- frozen: the blink phase comes from `life`, and a life paused in an "off"
-- phase would leave it invisible for the whole breather.
function Pickup:blinkedOff()
  return not self.frozen and self.life < PU.blinkAt and math.floor(self.life * 8) % 2 == 0
end

-- Shadow layer (src/post.lua): a disc the size of the badge, offset
-- down-right (drawIcon sets its own colors, so it can't be the silhouette).
function Pickup:drawShadow()
  if self:blinkedOff() then return end
  local s = Config.ART.size.pickup
  local dx, dy = Post.shadowOffset(s)
  love.graphics.circle("fill", self.x + dx, self.y + math.sin(self.bob) * 2 + dy, s * 0.5)
end

-- Glow layer (src/post.lua): a pulsing halo so drops stand out from enemies
-- and debris.
function Pickup:drawGlow()
  if self:blinkedOff() then return end
  local c = self.def.color
  love.graphics.setColor(c[1], c[2], c[3], EMIT.pickup * (0.75 + 0.25 * math.sin(self.bob * 1.5)))
  love.graphics.circle("fill", self.x, self.y + math.sin(self.bob) * 2, Config.ART.size.pickup * 0.85)
end

return Pickup
