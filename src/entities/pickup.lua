-- Power-up caído no chão. Pooled.

local Config = require("src.config")
local Assets = require("src.assets")
local UI     = require("src.ui")
local Post   = require("src.post")
local Shaders = require("src.shaders")

local PU = Config.POWERUP
local EMIT = Config.FX.emit
local FXP = Config.FX.pickup

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
    blinkPhase = 0,     -- white blink clock (cycles), speeds up near the end
    vanish = 0,         -- s left of the dissolve after the life ran out
    age = 0,            -- s since dropped (drop pop), runs in the breather too
    sheenT = 0,         -- sheen clock, random phase so pickups glint apart
  }, Pickup)
end

function Pickup:reset(x, y, def)
  self.x, self.y = x, y
  self.def = def
  self.life = PU.pickupLife
  self.bob = math.random() * math.pi * 2
  self.dead = false
  self.blinkPhase = 0
  self.vanish = 0
  self.age = 0
  self.sheenT = math.random() * FXP.sheenEvery
end

-- Drop pop: 0 -> popPeak (fast, eased out) -> 1 over popTime, then 1.
function Pickup:scale()
  local t = self.age / FXP.popTime
  if t >= 1 then return 1 end
  if t < 0.6 then
    local k = t / 0.6
    return FXP.popPeak * (1 - (1 - k) * (1 - k))
  end
  return FXP.popPeak + (1 - FXP.popPeak) * ((t - 0.6) / 0.4)
end

-- Devolve false quando some (o pool recolhe). `frozen` = respiro entre
-- waves: o pickup continua flutuando, mas o tempo de vida não corre.
-- When the life runs out it dissolves for Config.FX.dissolve.pickupVanish s
-- and can still be picked up meanwhile (a last chance).
function Pickup:update(dt, frozen)
  self.frozen = frozen and true or false
  if not frozen then
    if self.life > 0 then
      self.life = self.life - dt
      if self.life <= 0 then
        self.vanish = Config.FX.dissolve.pickupVanish
      elseif self.life < PU.blinkAt then
        -- Blink rate: blinkRateMin when it starts, blinkRateMax at the end.
        local k = self.life / PU.blinkAt
        self.blinkPhase = self.blinkPhase + dt * (PU.blinkRateMax + (PU.blinkRateMin - PU.blinkRateMax) * k)
      end
    else
      self.vanish = self.vanish - dt
    end
  end
  self.bob = self.bob + dt * 4
  self.age = self.age + dt
  self.sheenT = self.sheenT + dt
  return (self.life > 0 or self.vanish > 0) and not self.dead
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

-- 0..1 left of the final dissolve (1 = whole), or nil while still alive.
function Pickup:vanishing()
  if self.life > 0 then return nil end
  return math.max(0, self.vanish / Config.FX.dissolve.pickupVanish)
end

-- In its last seconds a white ring blinks around it (it never disappears, so it can't be
-- lost in the chaos), faster as the end nears. Not while frozen.
function Pickup:blinkOn()
  return not self.frozen and self.life > 0 and self.life < PU.blinkAt
    and self.blinkPhase % 1 < 0.5
end

-- Band position (0..1 along the badge diagonal) of the sheen sweeping now,
-- or nil between sweeps.
function Pickup:sheenPos()
  local t = self.sheenT % FXP.sheenEvery
  if t >= FXP.sheenTime then return nil end
  return -0.2 + 1.4 * (t / FXP.sheenTime)
end

function Pickup:draw()
  -- Gentle float; the halo is in :drawGlow. Drawn around the origin so the
  -- drop pop scales the whole icon (letter included).
  local g = love.graphics
  local s = Config.ART.size.pickup
  g.push()
  g.translate(self.x, self.y + math.sin(self.bob) * 2)
  local sc = self:scale()
  g.scale(sc, sc)
  local k = self:vanishing()
  if k then
    -- Life over: dissolves away with its color at the front (still pickable).
    if Shaders.dissolve(k, self.def.color) then
      Pickup.drawIcon(self.def, 0, 0, s)
    else
      Pickup.drawIcon(self.def, 0, 0, s, k)
    end
    Shaders.reset()
    g.pop()
    return
  end
  Pickup.drawIcon(self.def, 0, 0, s)
  -- Sheen: a white band sweeping across the badge (additive, badge-masked).
  local pos = self:sheenPos()
  if pos and Shaders.sheen(pos) then
    g.setBlendMode("add")
    UI.badge(self.def.color, 0, 0, s, FXP.sheenAlpha)
    g.setBlendMode("alpha")
    Shaders.reset()
  end
  if self:blinkOn() then
    -- A white ring around the badge (over it would hide the letter).
    g.setColor(1, 1, 1, FXP.blinkAlpha)
    g.setLineWidth(FXP.blinkWidth)
    g.circle("line", 0, 0, s * FXP.blinkRing)
    g.setLineWidth(1)
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
end

-- Shadow layer (src/post.lua): a disc the size of the badge, offset
-- down-right (drawIcon sets its own colors, so it can't be the silhouette).
-- None while it dissolves.
function Pickup:drawShadow()
  if self:vanishing() then return end
  local s = Config.ART.size.pickup * self:scale()
  local dx, dy = Post.shadowOffset(s)
  love.graphics.circle("fill", self.x + dx, self.y + math.sin(self.bob) * 2 + dy, s * 0.5)
end

-- Glow layer (src/post.lua): a pulsing halo so drops stand out from enemies
-- and debris; stronger on each white blink, fading with the dissolve.
function Pickup:drawGlow()
  local c = self.def.color
  local a = EMIT.pickup * (0.75 + 0.25 * math.sin(self.bob * 1.5))
  if self:blinkOn() then a = math.min(1, a * FXP.blinkGlow) end
  local k = self:vanishing()
  if k then a = a * k end
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", self.x, self.y + math.sin(self.bob) * 2,
    Config.ART.size.pickup * FXP.glowSize * self:scale())
end

return Pickup
