-- Particles. Pooled: only re-initialized, never re-created.
--
-- Kinds sharing the pool (tuning in Config.JUICE):
--   "spark"  -- additive streak stretched along its velocity, white-hot
--               cooling to its color (explosions, bursts, impacts);
--   "fire"   -- additive Kenney puff, white -> hot -> color, grows and fades;
--   "flash"  -- additive white core flash, a few frames long;
--   "smoke"  -- dark puff (alpha blend) that lingers a little;
--   "debris" -- a quadrant of a ship sprite, spinning away (tank/player/boss);
--   "trail"  -- missile smoke puff tinted with the missile color.
--
-- Layers (Game:draw): Particle.drawUnder (smoke, trail, debris) goes under
-- the enemies; Particle.drawOver (sparks, fire, flash) goes over the whole
-- arena; Particle.drawGlow adds their light to the glow layer.
--
-- Low-priority particles (smoke, debris, impact sparks, trails) only spawn
-- below a share of the pool (J.poolShare), so they never starve explosions.

local Config  = require("src.config")
local Util    = require("src.util")
local Assets  = require("src.assets")
local Shaders = require("src.shaders")

local J = Config.JUICE
local EMIT = Config.FX.emit
local SP, FI, SM, DB, IM, RAMP = J.spark, J.fire, J.smoke, J.debris, J.impact, J.ramp
local SHARE = J.poolShare

local PUFFS = { "puff1", "puff2", "puff3", "puff4" }
local TAU = math.pi * 2
local sqrt, atan2, rand = math.sqrt, math.atan2, Util.randRange

local DRAG = { spark = SP.drag, fire = FI.drag, smoke = SM.drag, debris = DB.drag, flash = 0, trail = 0 }

local Particle = {}
Particle.__index = Particle

function Particle.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0, maxLife = 1,
    size = J.particleSize,
    color = Config.COLORS.flash,
    kind = "spark",
    sprite = PUFFS[1],   -- puff sprite, or the sprite role for debris
    quad = 1,            -- debris: which quadrant
    recolor = false,     -- debris: draw through the recolor shader
    rot = 0, spin = 0,
  }, Particle)
end

function Particle:reset(kind, x, y, vx, vy, life, size, color)
  self.kind = kind
  self.x, self.y = x, y
  self.vx, self.vy = vx, vy
  self.life, self.maxLife = life, life
  self.size = size
  self.color = color or Config.COLORS.flash
  self.spin = 0
  if kind == "fire" or kind == "smoke" or kind == "trail" then
    self.sprite = PUFFS[math.random(#PUFFS)]
    self.rot = math.random() * TAU
    local spin = kind == "smoke" and SM.spin or FI.spin
    self.spin = rand(-spin, spin)
  end
end

-- Room for a low-priority particle: the pool is below `share` of its size.
local function room(pool, share)
  return pool.count < pool.capacity * share
end

local function spawn(pool, kind, x, y, vx, vy, life, size, color)
  local p = pool:acquire()
  if not p then return nil end   -- pool full: drop it, never allocate
  p:reset(kind, x, y, vx, vy, life, size, color)
  return p
end

-- `n` particles of `kind` flying out of (x, y) in random directions.
local function scatter(pool, kind, n, x, y, speedMin, speedMax, lifeMin, lifeMax, size, sizeVar, color)
  for _ = 1, n do
    local a = math.random() * TAU
    local s = rand(speedMin, speedMax)
    local sz = sizeVar and size * rand(0.7, 1.1) or size
    if not spawn(pool, kind, x, y, math.cos(a) * s, math.sin(a) * s,
      rand(lifeMin, lifeMax), sz, color) then
      return false
    end
  end
  return true
end

-- Scatters `count` sparks from a point (pickups, cleared shots, spawns...).
function Particle.burst(pool, count, x, y, color, size)
  scatter(pool, "spark", count, x, y, SP.speedMin, SP.speedMax, SP.lifeMin, SP.lifeMax,
    size or J.particleSize, false, color)
end

-- Explosion from a Config.JUICE.explosions preset, sizes times `scale`.
-- Emitted flash -> fire -> sparks -> smoke, so a nearly full pool drops the
-- smoke first. (The shock ring is world:explosion's job.)
function Particle.explosion(pool, x, y, color, preset, scale)
  local k = scale or 1
  if preset.flash > 0 then
    if not spawn(pool, "flash", x, y, 0, 0, J.flashLife, preset.flash * k, color) then return end
  end
  if not scatter(pool, "fire", preset.fire, x, y, FI.speedMin, FI.speedMax,
    FI.lifeMin, FI.lifeMax, preset.fireSize * k, true, color) then return end
  if not scatter(pool, "spark", preset.sparks, x, y, SP.speedMin, SP.speedMax,
    SP.lifeMin, SP.lifeMax, preset.sparkSize, false, color) then return end
  if room(pool, SHARE.smoke) then
    scatter(pool, "smoke", preset.smoke, x, y, SM.speedMin, SM.speedMax,
      SM.lifeMin, SM.lifeMax, preset.smokeSize * k, true, color)
  end
end

-- A sprite breaking apart: its 4 quadrants fly out from where they are on
-- the ship, spinning. `angle`/`size` as in Assets.draw; `recolor` draws them
-- through the palette swap in `color` (player and boss ships), otherwise
-- `color` tints them (white simpleSpace sprites).
function Particle.debris(pool, role, x, y, angle, size, color, recolor)
  if not room(pool, SHARE.debris) then return end
  local s = Assets.sprite(role)
  if not s or not s.quads then return end
  local k = size / math.max(s.w, s.h)
  local r = angle - s.rot
  local cr, sr = math.cos(r), math.sin(r)
  for q = 1, 4 do
    local sg = Assets.QUADRANT_SIGNS[q]
    local ox, oy = sg[1] * s.w * 0.25 * k, sg[2] * s.h * 0.25 * k
    local wx, wy = ox * cr - oy * sr, ox * sr + oy * cr
    local nx, ny = Util.normalize(wx, wy)
    local v = rand(DB.speedMin, DB.speedMax)
    local p = spawn(pool, "debris", x + wx, y + wy, nx * v, ny * v,
      rand(DB.lifeMin, DB.lifeMax), size, color)
    if not p then return end
    p.sprite, p.quad, p.recolor = role, q, recolor or false
    p.rot, p.spin = angle, rand(-DB.spin, DB.spin)
  end
end

-- Impact: a couple of short sparks bouncing back against a shot moving
-- along (dirX, dirY). Skipped while the pool is busy.
function Particle.impact(pool, x, y, dirX, dirY, color)
  if not room(pool, SHARE.impact) then return end
  local base = atan2(-dirY, -dirX)
  for _ = 1, IM.count do
    local a = base + rand(-IM.spread, IM.spread)
    local s = rand(IM.speedMin, IM.speedMax)
    if not spawn(pool, "spark", x, y, math.cos(a) * s, math.sin(a) * s,
      rand(IM.lifeMin, IM.lifeMax), IM.size, color) then
      return
    end
  end
end

-- One small trail puff left behind a moving object (missiles).
function Particle.trail(pool, x, y, color)
  spawn(pool, "trail", x, y, 0, 0, J.trailLife, J.trailSize, color)
end

function Particle:update(dt)
  self.life = self.life - dt
  if self.life <= 0 then return false end
  -- Simple exponential drag: fast at first, settles at the end.
  local drag = 1 - DRAG[self.kind] * dt
  if drag < 0 then drag = 0 end
  self.vx, self.vy = self.vx * drag, self.vy * drag
  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt
  self.rot = self.rot + self.spin * dt
  return true
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Color over life `a` (0 = born, 1 = gone): white -> hot -> `c`.
local function ramp(c, a)
  local hot = RAMP.hot
  if a < RAMP.hotEnd then
    local k = a / RAMP.hotEnd
    return 1 + (hot[1] - 1) * k, 1 + (hot[2] - 1) * k, 1 + (hot[3] - 1) * k
  elseif a < RAMP.colorEnd then
    local k = (a - RAMP.hotEnd) / (RAMP.colorEnd - RAMP.hotEnd)
    return hot[1] + (c[1] - hot[1]) * k, hot[2] + (c[2] - hot[2]) * k, hot[3] + (c[3] - hot[3]) * k
  end
  return c[1], c[2], c[3]
end

-- Spark streak: the 1x1 white texel stretched along the velocity. One
-- texture for every spark, so LÖVE batches them.
local function streak(p, a, lenMul, widthMul)
  local len = sqrt(p.vx * p.vx + p.vy * p.vy) * SP.stretch
  if len < SP.minLen then len = SP.minLen end
  love.graphics.draw(Assets.white, p.x, p.y, atan2(p.vy, p.vx),
    len * lenMul, p.size * (1 - a * 0.5) * widthMul, 0.5, 0.5)
end

-- Under the enemies: dark smoke, missile trails and debris.
function Particle.drawUnder(pool)
  local g = love.graphics
  local items = pool.items
  for i = 1, pool.count do
    local p = items[i]
    local kind = p.kind
    if kind == "smoke" then
      local a = 1 - p.life / p.maxLife
      local c, d = p.color, SM.darken
      g.setColor(c[1] * d, c[2] * d, c[3] * d, (1 - a) * SM.alpha)
      Assets.draw(p.sprite, p.x, p.y, p.rot, p.size * (1 + a * SM.grow))
    elseif kind == "trail" then
      local t = p.life / p.maxLife
      local c = p.color
      g.setColor(c[1], c[2], c[3], t * J.trailAlpha)
      Assets.draw(p.sprite, p.x, p.y, p.rot, p.size * (1 + (1 - t) * 0.8))
    elseif kind == "debris" then
      local alpha = math.min(1, (p.life / p.maxLife) * 2.5)   -- fades in its last 40%
      if p.recolor then
        Shaders.recolor(p.color)
        g.setColor(1, 1, 1, alpha)
      else
        local c = p.color
        g.setColor(c[1], c[2], c[3], alpha)
      end
      Assets.drawQuadrant(p.sprite, p.quad, p.x, p.y, p.rot, p.size)
      if p.recolor then Shaders.reset() end
    end
  end
end

-- Over the arena, additive, grouped by kind (sparks share one texture).
function Particle.drawOver(pool)
  local g = love.graphics
  local items, n = pool.items, pool.count
  g.setBlendMode("add")
  for i = 1, n do
    local p = items[i]
    if p.kind == "spark" then
      local a = 1 - p.life / p.maxLife
      local r, gg, b = ramp(p.color, a)
      g.setColor(r, gg, b, 1 - a * a)
      streak(p, a, 1, 1)
    end
  end
  for i = 1, n do
    local p = items[i]
    if p.kind == "fire" then
      local a = 1 - p.life / p.maxLife
      local r, gg, b = ramp(p.color, a)
      g.setColor(r, gg, b, (1 - a) * FI.alpha)
      Assets.draw(p.sprite, p.x, p.y, p.rot, p.size * (1 + a * FI.grow))
    end
  end
  for i = 1, n do
    local p = items[i]
    if p.kind == "flash" then
      local a = 1 - p.life / p.maxLife
      g.setColor(1, 1, 1, (1 - a) * J.flashAlpha)
      g.circle("fill", p.x, p.y, p.size * 0.5 * (0.7 + 0.3 * a))
    end
  end
  g.setBlendMode("alpha")
end

-- Glow layer (src/post.lua, already additive): sparks, fire and flashes.
function Particle.drawGlow(pool)
  local g = love.graphics
  local items = pool.items
  for i = 1, pool.count do
    local p = items[i]
    local kind = p.kind
    if kind == "spark" then
      local a = 1 - p.life / p.maxLife
      local r, gg, b = ramp(p.color, a)
      g.setColor(r, gg, b, (1 - a) * EMIT.spark)
      streak(p, a, 1.2, 2.5)
    elseif kind == "fire" then
      local a = 1 - p.life / p.maxLife
      local r, gg, b = ramp(p.color, a)
      g.setColor(r, gg, b, (1 - a) * EMIT.fire)
      g.circle("fill", p.x, p.y, p.size * 0.5 * (1 + a * FI.grow))
    elseif kind == "flash" then
      local a = 1 - p.life / p.maxLife
      g.setColor(1, 1, 1, (1 - a) * EMIT.flash)
      g.circle("fill", p.x, p.y, p.size * 0.6)
    end
  end
end

return Particle
