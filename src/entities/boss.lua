-- Boss: one big ship every Config.BOSS.every waves.
--
-- A single instance, created once and reused (`active`), kept OUT of the
-- enemy pool and the collision grid: it is far bigger than a grid cell and it
-- enters from outside the arena, which pooled enemies are clamped against.
-- It exposes the same target fields as an Enemy (x, y, radius, dead) so
-- combat, the auto-aim and the player missiles test it explicitly the same
-- way they test enemies.
--
-- States:
--   "idle"  -- not in play
--   "warn"  -- ALERTA banner, still offscreen
--   "enter" -- slides in from a random side: holds fire, takes no damage
--   "fight" -- roams slowly, aimed bursts + homing missiles, rage at low HP
--   "dying" -- chain of small blasts over the hull, then the big one
--   "done"  -- the spawner closes the wave and calls Boss:clear()

local Config     = require("src.config")
local Util       = require("src.util")
local Audio      = require("src.audio")
local Assets     = require("src.assets")
local Shaders    = require("src.shaders")
local Music      = require("src.music")
local Background = require("src.background")
local Combo      = require("src.systems.combo")

local B = Config.BOSS
local V = Config.bossValue
local floor = math.floor

local Boss = {}
Boss.__index = Boss

function Boss.new()
  return setmetatable({
    active = false,
    state = "idle",
    dead = true,          -- true unless it can be hit (auto-aim, missiles, blasts)
    n = 1,                -- which boss this is (1 = wave 10)
    wave = 0,
    variant = B.variants[1],
    x = 0, y = 0, angle = math.pi / 2,
    size = B.size, radius = B.size * B.radiusFrac,
    hp = 1, maxHp = 1,
    flash = 0,
    sputter = 1,          -- engine alpha this frame (dying sputter), set by draw
    timer = 0,            -- time left in "warn" / "dying"
    goalX = 0, goalY = 0, pause = 0,
    burstTimer = 0, volleysLeft = 0, volleyTimer = 0, burstTarget = nil,
    missileTimer = 0,
    targetTurn = 0,       -- round-robin over the players
    lookAt = nil,         -- player the sprite turns toward
    blastTimer = 0,
    thrust = 0,           -- engine flame length factor, eased (see B.engine)
    engineT = 0,          -- drives the flame flicker
    damageBy = { 0, 0 },
    -- Values for boss n, resolved once in begin().
    s = {},
  }, Boss)
end

function Boss:clear()
  self.active = false
  self.state = "idle"
  self.dead = true
end

function Boss:isFighting()
  return self.state == "fight"
end

function Boss:isRaging()
  return self.state == "fight" and self.hp < self.maxHp * B.rage.below
end

-- HP left as 0..1 (HUD bar).
function Boss:fraction()
  return math.max(0, self.hp / self.maxHp)
end

-- Next live player, round-robin: in 2P every burst/missile picks the other
-- one, so nobody rides along.
local function nextTarget(self, world)
  local n = world.playerCount
  for _ = 1, n do
    self.targetTurn = self.targetTurn % n + 1
    local p = world.players[self.targetTurn]
    if p and p.alive then return p end
  end
  return nil
end

-- Roaming area: where the center may go with the whole hull inside the
-- arena (collapses to the arena center if the boss is too big for it).
local function roamBounds(self, world)
  local a = world.arena
  local half = self.size * 0.5 + B.margin
  local x0, x1 = a.x + half, a.x + a.w - half
  local y0, y1 = a.y + half, a.y + a.h - half
  if x0 > x1 then x0, x1 = a.cx, a.cx end
  if y0 > y1 then y0, y1 = a.cy, a.cy end
  return x0, x1, y0, y1
end

local function pickGoal(self, world)
  local x0, x1, y0, y1 = roamBounds(self, world)
  self.goalX = Util.randRange(x0, x1)
  self.goalY = Util.randRange(y0, y1)
end

-- Starts boss `n` on wave `wave`: resolves its numbers, picks the variant and
-- puts it offscreen on a random side, behind the ALERTA banner.
function Boss:begin(world, n, wave)
  local nv = #B.variants
  self.n, self.wave = n, wave
  self.variant = B.variants[(n - 1) % nv + 1]
  self.size = B.size * (1 + B.growPerCycle * floor((n - 1) / nv))
  self.radius = self.size * B.radiusFrac

  local s = self.s
  s.hp = floor(V(B.hp, n))
  s.speed = V(B.speed, n)
  s.points = floor(V(B.points, n))
  s.drops = floor(V(B.drops, n))
  s.burstInterval = V(B.burst.interval, n)
  s.burstCount = floor(V(B.burst.count, n))
  s.fan = floor(V(B.burst.fan, n))
  s.bulletSpeed = V(B.burst.bulletSpeed, n)
  s.missileInterval = V(B.missile.interval, n)
  s.missileMax = floor(V(B.missile.maxAlive, n))

  self.hp, self.maxHp = s.hp, s.hp
  self.active = true
  self.state = "warn"
  self.dead = true
  self.timer = B.warnTime
  self.flash = 0
  self.damageBy[1], self.damageBy[2] = 0, 0
  self.volleysLeft = 0
  self.thrust = B.engine.enter
  self.burstTimer = s.burstInterval * 0.5
  self.missileTimer = s.missileInterval * 0.6
  self.lookAt = nil

  -- Entrance: the middle of a random side, fully outside. The goal is the
  -- first point where the whole hull is inside the roaming area.
  local a = world.arena
  local out = self.size * 0.5 + 4
  local x0, x1, y0, y1 = roamBounds(self, world)
  local side = Util.randInt(1, 4)
  if side == 1 then      -- top (behind the HUD strip)
    self.x, self.y, self.goalX, self.goalY = a.cx, a.y - out, a.cx, y0
  elseif side == 2 then  -- bottom
    self.x, self.y, self.goalX, self.goalY = a.cx, a.y + a.h + out, a.cx, y1
  elseif side == 3 then  -- left
    self.x, self.y, self.goalX, self.goalY = a.x - out, a.cy, x0, a.cy
  else                   -- right
    self.x, self.y, self.goalX, self.goalY = a.x + a.w + out, a.cy, x1, a.cy
  end
  self.angle = math.atan2(self.goalY - self.y, self.goalX - self.x)

  Audio.play("boss_alarm")
  Background.pulse(a.cx, a.cy, Config.ART.background.grid.waveStart)
end

-- ---------------------------------------------------------------------------
-- Attacks
-- ---------------------------------------------------------------------------

-- Muzzle: a bit ahead of the center along the facing.
local function muzzle(self)
  local d = self.size * 0.3
  return self.x + math.cos(self.angle) * d, self.y + math.sin(self.angle) * d
end

local function fireVolley(self, world, target)
  local mx, my = muzzle(self)
  local base = math.atan2(target.y - my, target.x - mx)
  local n = self.s.fan
  local spread = n > 1 and B.burst.fanAngle or 0
  local step = n > 1 and spread / (n - 1) or 0
  local start = base - spread * 0.5
  for i = 1, n do
    local a = start + step * (i - 1)
    world:spawnBullet(mx, my, math.cos(a), math.sin(a), self.s.bulletSpeed, 1,
      "enemy", "enemy", B.burst.bulletLife)
  end
  Audio.play("boss_shot")
end

local function countMissiles(world)
  local bullets, n = world.bullets, 0
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.kind == "bossMissile" and not b.dead then n = n + 1 end
  end
  return n
end

local function launchMissile(self, world, target)
  local mx, my = muzzle(self)
  -- Leaves sideways (random side), then curves in: reads as a launch, and the
  -- player sees it coming before it locks on.
  local a = math.atan2(target.y - my, target.x - mx) + (math.random() < 0.5 and -1 or 1) * math.rad(70)
  local M = B.missile
  local b = world:spawnBullet(mx, my, math.cos(a), math.sin(a), M.speed, 1,
    "enemy", "bossMissile", M.homingTime + M.failTime, M.radius, Config.COLORS.bulletEnemy)
  if not b then return end
  b.hp = M.hp
  b.target = target
  Audio.play("boss_missile")
end

local function attack(self, dt, world, rage)
  local fireMul = rage and B.rage.fireMul or 1
  local missileMul = rage and B.rage.missileMul or 1

  -- Bursts: the volley loop runs on its own clock so the gap stays fixed.
  if self.volleysLeft > 0 then
    self.volleyTimer = self.volleyTimer - dt
    if self.volleyTimer <= 0 then
      local t = self.burstTarget
      if not t or not t.alive then t = nextTarget(self, world); self.burstTarget = t end
      if t then fireVolley(self, world, t) end
      self.volleysLeft = self.volleysLeft - 1
      self.volleyTimer = B.burst.gap
    end
  else
    self.burstTimer = self.burstTimer - dt * fireMul
    if self.burstTimer <= 0 then
      self.burstTimer = self.s.burstInterval
      self.burstTarget = nextTarget(self, world)
      if self.burstTarget then
        self.volleysLeft = self.s.burstCount
        self.volleyTimer = 0
        self.lookAt = self.burstTarget
      end
    end
  end

  self.missileTimer = self.missileTimer - dt * missileMul
  if self.missileTimer <= 0 then
    self.missileTimer = self.s.missileInterval
    if countMissiles(world) < self.s.missileMax then
      local t = nextTarget(self, world)
      if t then launchMissile(self, world, t) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Damage and death
-- ---------------------------------------------------------------------------

-- A hit from player `owner` (1 or 2). Ignored unless fighting. Keeps that
-- player's combo alive. Returns true if this hit killed it.
function Boss:hit(amount, owner, world)
  if self.state ~= "fight" then return false end
  local dealt = math.min(amount, self.hp)
  self.hp = self.hp - amount
  self.flash = Config.ENEMY_FLASH_TIME
  if type(owner) == "number" then
    self.damageBy[owner] = (self.damageBy[owner] or 0) + dealt
    local p = world.players[owner]
    if p then Combo.keep(p) end
  end
  if self.hp <= 0 then
    self:startDeath(world)
    return true
  end
  Audio.play("boss_hit")
  return false
end

-- Debug (F2) and the HP hitting zero.
function Boss:startDeath(world)
  if self.state == "dying" or self.state == "done" or not self.active then return end
  self.hp = 0
  self.state = "dying"
  self.dead = true
  self.timer = B.death.time
  self.blastTimer = 0
  self.volleysLeft = 0
  -- Everything hostile goes with it: the fight is over.
  world:clearHostiles()
end

local function finale(self, world)
  local x, y, c = self.x, self.y, self.variant.color
  world:explosion(x, y, c, 10, self.size * 0.45, 20, 6)
  world:explosion(x, y, Config.COLORS.flash, 4, self.size * 0.3, 10, 4)
  world:shake(B.death.shake, true)
  world:hitStop(B.death.hitStop, true)
  Background.pulse(x, y, B.death.pulse)
  Audio.play("boss_die")

  -- Points split by each player's share of the damage.
  local total = 0
  for i = 1, world.playerCount do total = total + (self.damageBy[i] or 0) end
  if total > 0 then
    for i = 1, world.playerCount do
      local share = (self.damageBy[i] or 0) / total
      world:addScore(i, floor(self.s.points * share + 0.5))
    end
  end

  -- Power-ups out of the wreck, kept inside the arena.
  local a = world.arena
  local m = 20
  for _ = 1, self.s.drops do
    local px = Util.clamp(x + Util.randRange(-self.size * 0.3, self.size * 0.3), a.x + m, a.x + a.w - m)
    local py = Util.clamp(y + Util.randRange(-self.size * 0.3, self.size * 0.3), a.y + m, a.y + a.h - m)
    world:dropPowerup(px, py, true)
  end

  -- The sky moves on to the next block's palette right away.
  Background.setTheme(Background.themeForWave(self.wave + 1))
  Music.play("game")
  if Config.SMOKE then require("src.smoke").bump("bosses") end
  self.state = "done"
  self.dead = true
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function Boss:update(dt, world)
  if not self.active then return end
  if self.flash > 0 then self.flash = self.flash - dt end
  self.engineT = self.engineT + dt

  -- Engine flame length: long while sliding in, idle while stopped, cruise
  -- while roaming; eased so it swells and settles instead of popping.
  local E = B.engine
  local thrustWant = E.idle
  if self.state == "enter" or self.state == "warn" then
    thrustWant = E.enter
  elseif self.state == "fight" and self.pause <= 0 then
    thrustWant = E.cruise
  end
  self.thrust = self.thrust + (thrustWant - self.thrust) * math.min(1, E.ease * dt)

  local st = self.state
  if st == "warn" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self.state = "enter" end

  elseif st == "enter" then
    local dx, dy = self.goalX - self.x, self.goalY - self.y
    local nx, ny, dist = Util.normalize(dx, dy)
    local step = B.enterSpeed * dt
    if dist <= step then
      self.x, self.y = self.goalX, self.goalY
      self.state = "fight"
      self.dead = false
      -- The wave music plays through ALERTA and the entrance; the boss track
      -- fades in (Config.MUSIC.tracks.boss.fadeIn) only when the fight starts.
      Music.play("boss")
      self.pause = Util.randRange(B.pauseMin, B.pauseMax)
      pickGoal(self, world)
    else
      self.x, self.y = self.x + nx * step, self.y + ny * step
    end

  elseif st == "fight" then
    local rage = self:isRaging()
    -- Roam: go to a point, wait a little, pick the next one.
    if self.pause > 0 then
      self.pause = self.pause - dt
    else
      local nx, ny, dist = Util.normalize(self.goalX - self.x, self.goalY - self.y)
      local step = self.s.speed * (rage and B.rage.speedMul or 1) * dt
      if dist <= step then
        self.x, self.y = self.goalX, self.goalY
        self.pause = Util.randRange(B.pauseMin, B.pauseMax)
        pickGoal(self, world)
      else
        self.x, self.y = self.x + nx * step, self.y + ny * step
      end
    end
    attack(self, dt, world, rage)

    local t = self.lookAt
    if not t or not t.alive then t = world:nearestPlayer(self.x, self.y); self.lookAt = t end
    if t then
      local want = math.atan2(t.y - self.y, t.x - self.x)
      self.angle = Util.angleLerp(self.angle, want, math.min(1, B.turnRate * dt))
    end

  elseif st == "dying" then
    self.timer = self.timer - dt
    self.blastTimer = self.blastTimer - dt
    if self.blastTimer <= 0 then
      self.blastTimer = B.death.blastEvery
      local r = self.size * 0.35
      local bx = self.x + Util.randRange(-r, r)
      local by = self.y + Util.randRange(-r, r)
      world:explosion(bx, by, self.variant.color, 2, self.size * 0.18, 4, 4)
      world:shake(2)
      Audio.play("boss_blast")
    end
    if self.timer <= 0 then finale(self, world) end
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Engine flames behind each nozzle of the variant (drawn under the hull):
-- the player's two flickering flame frames, additive, an outer flame in the
-- variant color (redder while raging) and a white core. While dying they
-- sputter and shrink toward the final blast. The CALLER sets the additive
-- blend: this runs both in the arena pass and in the glow layer, where
-- `alphaMul` scales it and `coreMul` the white core (which would blow out
-- to a white blob once bloomed).
local function drawEngines(self, x, y, alphaMul, coreMul)
  local list = self.variant.engines
  if not list then return end
  local E = B.engine
  local g = love.graphics
  local spr = Assets.sprite(self.variant.sprite)
  local k = self.size / math.max(spr.w, spr.h)        -- texels -> px, as Assets.draw
  local a = self.angle
  local fx, fy = math.cos(a), math.sin(a)             -- forward (the sprite's +v)
  local rx, ry = math.sin(a), -math.cos(a)            -- the sprite's +u

  local stretch = self.thrust
  local alpha = self.sputter * alphaMul
  local c, l = self.variant.color, E.lighten
  local cr, cg, cb = c[1] + (1 - c[1]) * l, c[2] + (1 - c[2]) * l, c[3] + (1 - c[3]) * l
  if self:isRaging() then
    stretch = stretch * E.rageMul
    local t = E.rageTint
    cr, cg, cb = cr + (1 - cr) * t, cg * (1 - t), cb * (1 - t)
  end
  if self.state == "dying" then
    local left = self.timer / B.death.time            -- 1 -> 0
    stretch = stretch * (0.3 + 0.7 * left)
  end

  local frame = floor(self.engineT * Config.ART.engine.flickerRate) % 2 == 0
    and "engineFlame1" or "engineFlame2"
  for i = 1, #list do
    local n = list[i]
    -- Nozzle in world space: offset from the sprite center, rotated.
    local lx = (n[1] - 0.5) * spr.w * k
    local ly = (n[2] - 0.5) * spr.h * k
    local nx, ny = x + rx * lx + fx * ly, y + ry * lx + fy * ly
    local size = self.size * n[3]
    -- Flame center behind the nozzle, so it grows backward as it stretches.
    local back = size * 0.5 * stretch * 0.85
    g.setColor(cr, cg, cb, alpha)
    Assets.draw(frame, nx - fx * back, ny - fy * back, a + math.pi, size, 1, stretch)
    local core = size * E.coreScale
    back = core * 0.5 * stretch * 0.85
    g.setColor(1, 1, 1, E.coreAlpha * alpha * coreMul)
    Assets.draw(frame, nx - fx * back, ny - fy * back, a + math.pi, core, 1, stretch)
  end
end

-- Additive overlays with the hull sprite: white on hits and while dying, a
-- red pulse while raging. Returns their alphas (0 = off).
local function overlays(self)
  local white = 0
  if self.flash > 0 then white = 0.6 end
  if self.state == "dying" and floor(self.timer * 14) % 2 == 0 then white = 0.5 end
  local red = 0
  if self:isRaging() then
    local t = love.timer.getTime()
    red = 0.25 + 0.2 * math.sin(t * B.rage.pulseRate * math.pi * 2)
  end
  return white, red
end

function Boss:draw()
  if not self.active or self.state == "done" or self.state == "warn" then return end
  local g = love.graphics
  local x, y = self.x, self.y
  local role = self.variant.sprite

  -- Dying: shakes harder as the end nears, and the engines sputter. Kept
  -- for drawGlow, so the glow follows the same jitter this frame.
  self.sputter = 1
  if self.state == "dying" then
    local k = 1 - self.timer / B.death.time
    local j = 1 + 3 * k
    x, y = x + Util.randRange(-j, j), y + Util.randRange(-j, j)
    if math.random() < 0.35 then self.sputter = 0.25 end
  end
  self.drawX, self.drawY = x, y

  g.setBlendMode("add")
  drawEngines(self, x, y, 1, 1)
  g.setBlendMode("alpha")

  Shaders.recolor(self.variant.color)
  g.setColor(1, 1, 1, 1)
  Assets.draw(role, x, y, self.angle, self.size)
  Shaders.reset()

  local white, red = overlays(self)
  if white > 0 or red > 0 then
    g.setBlendMode("add")
    if red > 0 then
      g.setColor(1, 0.15, 0.1, red)
      Assets.draw(role, x, y, self.angle, self.size)
    end
    if white > 0 then
      g.setColor(1, 1, 1, white)
      Assets.draw(role, x, y, self.angle, self.size)
    end
    g.setBlendMode("alpha")
  end
  g.setColor(1, 1, 1, 1)
end

-- Glow layer (src/post.lua): engine flames, hit/death flash and rage pulse.
-- Uses the position Boss:draw picked this frame (dying jitter included).
function Boss:drawGlow()
  if not self.active or self.state == "done" or self.state == "warn" then return end
  local EMIT = Config.FX.emit
  local x, y = self.drawX or self.x, self.drawY or self.y
  local role = self.variant.sprite
  drawEngines(self, x, y, EMIT.engine, EMIT.engineCore)
  local white, red = overlays(self)
  if red > 0 then
    love.graphics.setColor(1, 0.15, 0.1, red * EMIT.rage)
    Assets.draw(role, x, y, self.angle, self.size)
  end
  if white > 0 then
    love.graphics.setColor(1, 1, 1, white * EMIT.hitFlash)
    Assets.draw(role, x, y, self.angle, self.size)
  end
end

function Boss:drawDebug()
  if not self.active then return end
  love.graphics.setColor(1, 0, 0, 0.6)
  love.graphics.circle("line", self.x, self.y, self.radius)
  love.graphics.setColor(1, 1, 1, 1)
end

return Boss
