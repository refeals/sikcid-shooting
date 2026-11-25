-- Inimigos. Um único tipo de objeto no pool; o comportamento vem de
-- BEHAVIORS[type], indexado por dados de Config.ENEMIES.
--
-- Manter todos os tipos num pool só evita 4 pools quase vazios e mantém a
-- colisão num loop linear.

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")
local Assets = require("src.assets")
local UI     = require("src.ui")
local Combat = require("src.systems.combat")
local Post   = require("src.post")
local Shaders = require("src.shaders")

local SIZE = Config.ART.size
local TURN_RATE = Config.ART.enemyTurnRate
local TANK_SPIN = Config.ART.tankSpin
local SP = Config.ENEMY_SPACING
local WD = Config.ENEMY_WANDER

local Enemy = {}
Enemy.__index = Enemy

local BEHAVIORS = {}

function Enemy.new()
  return setmetatable({
    type = "grunt",
    def = Config.ENEMIES.grunt,
    x = 0, y = 0, vx = 0, vy = 0,
    hp = 1,
    flash = 0,          -- tempo restante de flash branco ao levar dano
    target = nil,       -- jogador perseguido
    retarget = 0,
    fireTimer = 0,
    wobble = 0,
    dead = false,       -- flagged on death, swept by Combat at the end of the frame
    angle = 0,          -- drawn facing (visual only)
    space = 10,         -- half the drawn size: spacing between enemies
    wandering = false,  -- no live player: roaming (see wander)
    heading = 0,
    wantHeading = 0,
    wanderTimer = 0,
    -- Runner afterimages (Config.FX.trail): recent positions, newest first.
    echoX = {}, echoY = {}, echoA = {},
    echoN = 0, echoT = 0,
    materialize = 0,    -- s left of the spawn dissolve (set by the spawner)
    -- Kamikaze: "chase" | "aim" | "charge" | "stun", s left in it, the aim
    -- direction (frozen for the charge) and the stun spark timer.
    state = "chase", stateT = 0,
    aimX = 0, aimY = 0,
    sparkT = 0,
    phasing = false,    -- passes through the other enemies (kamikaze charge)
    harmless = 0,       -- s left with no deadly contact (divisor fragments)
    -- Sniper: the wall spot it heads for, and a throttle on re-picking it.
    goalX = 0, goalY = 0, hasGoal = false, repickT = 0,
    launchT = 0,        -- carrier: s until the next drone launch
    parent = nil,       -- carrier drone: the carrier that launched it
  }, Enemy)
end

function Enemy:reset(kind, x, y)
  local def = Config.ENEMIES[kind] or Config.ENEMIES.grunt
  self.type = kind
  self.def = def
  self.x, self.y = x, y
  self.vx, self.vy = 0, 0
  self.hp = def.hp
  self.flash = 0
  self.target = nil
  self.retarget = 0
  self.fireTimer = def.fireInterval and Util.randRange(0.3, def.fireInterval) or 0
  self.wobble = 0
  self.dead = false
  self.radius = def.radius
  self.color = Config.COLORS[def.color]
  self.angle = math.random() * math.pi * 2
  self.space = (SIZE[kind] or def.size) * 0.5
  self.wandering = false
  self.echoN, self.echoT = 0, 0
  self.materialize = 0
  self.state, self.stateT = "chase", 0
  self.aimX, self.aimY, self.sparkT = 0, 0, 0
  self.phasing = false
  self.harmless = 0
  self.hasGoal, self.repickT = false, 0
  self.launchT = def.launchInterval and Util.randRange(1.5, def.launchInterval) or 0
  self.parent = nil
end

-- Runners: samples the afterimage positions every echoEvery s (newest
-- first; tiny arrays, shifted).
function Enemy:sampleEchoes(dt)
  if self.type ~= "runner" then return end
  self.echoT = self.echoT - dt
  if self.echoT > 0 then return end
  local TR = Config.FX.trail
  self.echoT = TR.echoEvery
  local xs, ys, as = self.echoX, self.echoY, self.echoA
  local n = math.min(self.echoN + 1, TR.echoes)
  for i = n, 2, -1 do
    xs[i], ys[i], as[i] = xs[i - 1], ys[i - 1], as[i - 1]
  end
  xs[1], ys[1], as[1] = self.x, self.y, self.angle
  self.echoN = n
end

-- Runner afterimages: fading copies of the sprite at the sampled positions,
-- under the live enemies.
function Enemy:drawEchoes()
  if self.echoN == 0 then return end
  local TR = Config.FX.trail
  local size = SIZE[self.type] or SIZE.grunt
  local c = self.color
  for i = 1, self.echoN do
    love.graphics.setColor(c[1], c[2], c[3], TR.echoAlpha * (1 - (i - 1) / TR.echoes))
    Assets.draw(self.type, self.echoX[i], self.echoY[i], self.echoA[i], size)
  end
end

-- Escolhe (ou troca) o jogador perseguido.
local function pickTarget(self, world)
  self.target = world:nearestPlayer(self.x, self.y)
end

-- ---------------------------------------------------------------------------
-- Comportamentos
-- ---------------------------------------------------------------------------

-- Grunt: linha reta até o jogador mais próximo.
BEHAVIORS.grunt = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  self.vx, self.vy = nx * self.def.speed, ny * self.def.speed
end

-- Runner: rápido e errático; troca de alvo de tempos em tempos e oscila a
-- direção para não andar em linha reta.
BEHAVIORS.runner = function(self, dt, world)
  self.retarget = self.retarget - dt
  if self.retarget <= 0 or not self.target or not self.target.alive then
    self.target = world:randomPlayer() or world:nearestPlayer(self.x, self.y)
    self.retarget = Util.randRange(self.def.retargetMin, self.def.retargetMax)
  end
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end

  self.wobble = self.wobble + dt * 6
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  local a = math.atan2(ny, nx) + math.sin(self.wobble) * self.def.wobble
  self.vx, self.vy = math.cos(a) * self.def.speed, math.sin(a) * self.def.speed
end

-- Tank: lento e reto. O empurrão nos outros inimigos vem da separação
-- (massa maior), não de um caso especial aqui.
BEHAVIORS.tank = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local nx, ny = Util.normalize(t.x - self.x, t.y - self.y)
  self.vx, self.vy = nx * self.def.speed, ny * self.def.speed
end

-- Shooter: mantém ~120px de distância e atira projéteis lentos.
BEHAVIORS.shooter = function(self, dt, world)
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end

  local dx, dy = t.x - self.x, t.y - self.y
  local nx, ny, dist = Util.normalize(dx, dy)
  local keep = self.def.keepDistance
  local dir = 0
  if dist > keep + 20 then dir = 1 elseif dist < keep - 20 then dir = -1 end
  -- Anda em direção ao alvo (ou para longe) com um passo lateral, para não
  -- ficar parado quando já está na distância certa.
  local sx, sy = -ny, nx
  self.vx = (nx * dir + sx * 0.5) * self.def.speed
  self.vy = (ny * dir + sy * 0.5) * self.def.speed

  self.fireTimer = self.fireTimer - dt
  if self.fireTimer <= 0 then
    self.fireTimer = self.def.fireInterval
    world:spawnBullet(self.x, self.y, nx, ny, self.def.bulletSpeed, 1,
      "enemy", "enemy", self.def.bulletLife)
    Audio.play("shot_enemy")
  end
end

-- Kamikaze: chase -> aim (a red line; follows the target, then locks) ->
-- charge (straight, through the other enemies) -> chase. A wall during the
-- charge stuns it (see Enemy:update).
BEHAVIORS.kamikaze = function(self, dt, world)
  local def = self.def
  local s = self.state
  if s == "chase" then
    pickTarget(self, world)
    local t = self.target
    if not t then self.vx, self.vy = 0, 0; return end
    local nx, ny, dist = Util.normalize(t.x - self.x, t.y - self.y)
    if dist <= def.aimRange then
      self.state, self.stateT = "aim", def.aimTime
      self.aimX, self.aimY = nx, ny
      self.vx, self.vy = 0, 0
      Audio.play("kamikaze_aim")
      return
    end
    self.vx, self.vy = nx * def.speed, ny * def.speed
  elseif s == "aim" then
    self.vx, self.vy = 0, 0
    self.stateT = self.stateT - dt
    local t = self.target
    if self.stateT > def.lockTime and t and t.alive then
      local nx, ny, len = Util.normalize(t.x - self.x, t.y - self.y)
      if len > 0 then self.aimX, self.aimY = nx, ny end
    end
    if self.stateT <= 0 then
      self.state, self.stateT = "charge", def.chargeTime
      self.phasing = true
      Audio.play("kamikaze_charge")
      world:burst(4, self.x - self.aimX * 6, self.y - self.aimY * 6, self.color, 3)
      if Config.SMOKE then require("src.smoke").bump("charges") end
    end
  elseif s == "charge" then
    self.stateT = self.stateT - dt
    self.vx, self.vy = self.aimX * def.chargeSpeed, self.aimY * def.chargeSpeed
    if self.stateT <= 0 then
      self.state, self.phasing = "chase", false
    end
  else -- "stun"
    self.vx, self.vy = 0, 0
    self.stateT = self.stateT - dt
    self.sparkT = self.sparkT - dt
    if self.sparkT <= 0 then
      self.sparkT = def.sparkEvery
      world:burst(1, self.x, self.y, self.color, 2)
    end
    if self.stateT <= 0 then self.state = "chase" end
  end
end

-- Divisor fragment: flies out along its fan velocity while harmless, then
-- behaves like a small runner.
BEHAVIORS.fragment = function(self, dt, world)
  if self.harmless > 0 then return end
  BEHAVIORS.runner(self, dt, world)
end

-- Sniper spot: of `spotSamples` random points `wallInset` px inside the
-- walls, the one closest to the sniper among those at least `minRange` from
-- the target (so it runs along its wall rather than across the arena); with
-- none, the one farthest from the target.
local function pickSniperSpot(self, world, t)
  local def, a = self.def, world.arena
  local inset = def.wallInset
  local min2 = def.minRange * def.minRange
  local bx, by, bestD = nil, nil, math.huge
  local fx, fy, farD = self.x, self.y, -1
  for _ = 1, def.spotSamples do
    local x, y
    local side = math.random(4)
    if side == 1 then
      x, y = Util.randRange(a.x + inset, a.x + a.w - inset), a.y + inset
    elseif side == 2 then
      x, y = Util.randRange(a.x + inset, a.x + a.w - inset), a.y + a.h - inset
    elseif side == 3 then
      x, y = a.x + inset, Util.randRange(a.y + inset, a.y + a.h - inset)
    else
      x, y = a.x + a.w - inset, Util.randRange(a.y + inset, a.y + a.h - inset)
    end
    local toTarget = Util.dist2(x, y, t.x, t.y)
    if toTarget >= min2 then
      local d = Util.dist2(x, y, self.x, self.y)
      if d < bestD then bx, by, bestD = x, y, d end
    elseif toTarget > farD then
      fx, fy, farD = x, y, toTarget
    end
  end
  if bx then self.goalX, self.goalY = bx, by else self.goalX, self.goalY = fx, fy end
  self.hasGoal = true
  self.repickT = 0.4
end

-- Sniper: "chase" walks to a wall spot; there, once fireInterval is over, it
-- "aim"s a thin red line (follows the target, then locks) and fires one fast
-- shot, then picks a new spot. A target closer than fleeRange cancels the aim
-- (it runs instead of firing).
BEHAVIORS.sniper = function(self, dt, world)
  local def = self.def
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  if self.fireTimer > 0 then self.fireTimer = self.fireTimer - dt end
  if self.repickT > 0 then self.repickT = self.repickT - dt end
  local tooClose = Util.dist2(self.x, self.y, t.x, t.y) < def.fleeRange * def.fleeRange

  if self.state == "aim" then
    self.vx, self.vy = 0, 0
    if tooClose then
      self.state = "chase"
      pickSniperSpot(self, world, t)
      return
    end
    self.stateT = self.stateT - dt
    if self.stateT > def.lockTime then
      local nx, ny, len = Util.normalize(t.x - self.x, t.y - self.y)
      if len > 0 then self.aimX, self.aimY = nx, ny end
    end
    if self.stateT <= 0 then
      world:spawnBullet(self.x + self.aimX * 8, self.y + self.aimY * 8, self.aimX, self.aimY,
        def.bulletSpeed, 1, "enemy", "sniper", def.bulletLife, def.bulletRadius, Config.COLORS.sniperShot)
      Audio.play("sniper_shot")
      self.state, self.hasGoal = "chase", false
      self.fireTimer = def.fireInterval
      if Config.SMOKE then require("src.smoke").bump("snipes") end
    end
    return
  end

  -- Walking to the spot (a new one if the target got too close to it).
  if not self.hasGoal or (self.repickT <= 0
      and Util.dist2(self.goalX, self.goalY, t.x, t.y) < def.minRange * def.minRange) then
    pickSniperSpot(self, world, t)
  end
  local nx, ny, dist = Util.normalize(self.goalX - self.x, self.goalY - self.y)
  if dist > 6 then
    self.vx, self.vy = nx * def.speed, ny * def.speed
    return
  end
  self.vx, self.vy = 0, 0
  if self.fireTimer <= 0 and not tooClose then
    self.state, self.stateT = "aim", def.aimTime
    self.aimX, self.aimY = Util.normalize(t.x - self.x, t.y - self.y)
    Audio.play("sniper_aim")
  end
end

-- Carrier: launches up to launchCount drones out of its sides (perpendicular
-- to its facing), keeping at most maxDrones of its own alive. Spawned straight
-- into the pool: outside the wave quota.
local function launchDrones(self, world)
  local def = self.def
  local pool = world.enemies
  local alive = 0
  for i = 1, pool.count do
    local e = pool.items[i]
    if e.parent == self and not e.dead then alive = alive + 1 end
  end
  local n = math.min(def.launchCount, def.maxDrones - alive)
  if n <= 0 then return end
  local child = Config.ENEMIES[def.spawn]
  local px, py = -math.sin(self.angle), math.cos(self.angle)
  for i = 1, n do
    local s = i % 2 == 1 and 1 or -1
    local dx, dy = px * s, py * s
    local e = world:spawnEnemy(def.spawn, self.x + dx * def.hatchOffset, self.y + dy * def.hatchOffset)
    if not e then break end
    e.parent = self
    e.harmless = child.harmlessTime or 0
    e.heading = math.atan2(dy, dx)
    e.angle = e.heading
    e.vx, e.vy = dx * def.launchSpeed, dy * def.launchSpeed
  end
  Audio.play("carrier_launch")
  if Config.SMOKE then require("src.smoke").bump("launches") end
end

-- Carrier: holds keepDistance from its target (no strafing) and launches
-- drones every launchInterval s (the hatches blink before, see Enemy:draw).
BEHAVIORS.carrier = function(self, dt, world)
  local def = self.def
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local nx, ny, dist = Util.normalize(t.x - self.x, t.y - self.y)
  local keep = def.keepDistance
  local dir = 0
  if dist > keep + 20 then dir = 1 elseif dist < keep - 20 then dir = -1 end
  self.vx, self.vy = nx * dir * def.speed, ny * dir * def.speed

  self.launchT = self.launchT - dt
  if self.launchT <= 0 then
    self.launchT = def.launchInterval
    launchDrones(self, world)
  end
end

-- Carrier drone: flies out along its launch velocity while harmless, then
-- homes in on the nearest player, turning at most turnRate rad/s (so it
-- curves in instead of sticking to the player).
BEHAVIORS.scout = function(self, dt, world)
  if self.harmless > 0 then return end
  pickTarget(self, world)
  local t = self.target
  if not t then self.vx, self.vy = 0, 0; return end
  local want = math.atan2(t.y - self.y, t.x - self.x)
  self.heading = Util.turnToward(self.heading, want, self.def.turnRate * dt)
  self.vx = math.cos(self.heading) * self.def.speed
  self.vy = math.sin(self.heading) * self.def.speed
end

-- ---------------------------------------------------------------------------
-- No live player: roam instead of freezing. Starts along the current
-- heading, picks a new one every few seconds (pointing back inside near the
-- walls) and eases into it, at a reduced speed.
-- ---------------------------------------------------------------------------
local function wander(self, dt, world)
  if not self.wandering then
    self.wandering = true
    self.target = nil
    if self.vx ~= 0 or self.vy ~= 0 then
      self.heading = math.atan2(self.vy, self.vx)
    else
      self.heading = self.angle
    end
    self.wantHeading = self.heading
    self.wanderTimer = Util.randRange(WD.turnMin, WD.turnMax)
  end

  self.wanderTimer = self.wanderTimer - dt
  if self.wanderTimer <= 0 then
    self.wanderTimer = Util.randRange(WD.turnMin, WD.turnMax)
    local a, m = world.arena, WD.wallMargin
    if self.x < a.x + m or self.x > a.x + a.w - m or self.y < a.y + m or self.y > a.y + a.h - m then
      self.wantHeading = math.atan2(a.cy - self.y, a.cx - self.x)
        + Util.randRange(-WD.inwardSpread, WD.inwardSpread)
    else
      self.wantHeading = self.heading + Util.randRange(-WD.maxTurn, WD.maxTurn)
    end
  end

  self.heading = Util.turnToward(self.heading, self.wantHeading, WD.turnRate * dt)
  local speed = self.def.speed * WD.speedMul
  self.vx, self.vy = math.cos(self.heading) * speed, math.sin(self.heading) * speed
end

-- ---------------------------------------------------------------------------
-- Avoidance: bends the velocity away from neighbors closer than their two
-- spaces plus the gap (stronger the closer they are), keeping the speed.
-- The query callback is a module-level function fed by upvalues, so no
-- closure is created per enemy per frame.
-- ---------------------------------------------------------------------------
local avSelf, avX, avY = nil, 0, 0

local function avoidNeighbor(other)
  if other == avSelf or other.dead then return end
  local want = avSelf.space + other.space + SP.gap
  local dx, dy = avSelf.x - other.x, avSelf.y - other.y
  local d2 = dx * dx + dy * dy
  if d2 >= want * want then return end
  if d2 <= 0.0001 then
    -- Same spot (fresh batch at a door): the overlap fix splits them.
    return
  end
  local d = math.sqrt(d2)
  local k = (1 - d / want) / d
  avX, avY = avX + dx * k, avY + dy * k
end

local function avoid(self, world)
  local vx, vy = self.vx, self.vy
  if vx == 0 and vy == 0 then return end
  if self.phasing then return end   -- charging kamikaze: straight through
  avSelf, avX, avY = self, 0, 0
  Combat.queryCircle(self.x, self.y, self.space + SP.maxSpace + SP.gap, avoidNeighbor)

  local boss = world.boss
  if boss and (boss.state == "enter" or boss.state == "fight") then
    local want = self.space + boss.size * SP.bossFrac + SP.gap
    local dx, dy = self.x - boss.x, self.y - boss.y
    local d2 = dx * dx + dy * dy
    if d2 < want * want and d2 > 0.0001 then
      local d = math.sqrt(d2)
      local k = (1 - d / want) / d
      avX, avY = avX + dx * k, avY + dy * k
    end
  end
  avSelf = nil

  if avX == 0 and avY == 0 then return end
  local nx, ny, speed = Util.normalize(vx, vy)
  local fx, fy = Util.normalize(nx + avX * SP.steer, ny + avY * SP.steer)
  if fx == 0 and fy == 0 then return end
  self.vx, self.vy = fx * speed, fy * speed
end

-- ---------------------------------------------------------------------------
function Enemy:update(dt, world)
  if self.flash > 0 then self.flash = self.flash - dt end
  if self.materialize > 0 then self.materialize = self.materialize - dt end
  if self.harmless > 0 then self.harmless = self.harmless - dt end

  if world:nearestPlayer(self.x, self.y) then
    self.wandering = false
    local behavior = BEHAVIORS[self.type] or BEHAVIORS.grunt
    behavior(self, dt, world)
  else
    -- Nobody to aim at or charge: back to plain chasing once they return.
    self.state, self.phasing, self.hasGoal = "chase", false, false
    wander(self, dt, world)
  end
  avoid(self, world)

  self:sampleEchoes(dt)   -- before moving: the echoes trail behind
  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  -- Paredes: inimigo não sai da arena (mas pode nascer em cima da porta).
  local a, r = world.arena, self.radius
  local hitWall = false
  if self.x < a.x + r then self.x, hitWall = a.x + r, true end
  if self.x > a.x + a.w - r then self.x, hitWall = a.x + a.w - r, true end
  if self.y < a.y + r then self.y, hitWall = a.y + r, true end
  if self.y > a.y + a.h - r then self.y, hitWall = a.y + a.h - r, true end

  -- A charging kamikaze that hits a wall is stunned (sparks off the wall).
  if hitWall and self.state == "charge" then
    local def = self.def
    self.state, self.stateT = "stun", def.stunTime
    self.phasing, self.sparkT = false, 0
    self.vx, self.vy = 0, 0
    world:impact(self.x, self.y, self.aimX, self.aimY, self.color)
    world:shake(Config.JUICE.shakeEnemyDeath)
    Audio.play("kamikaze_stun")
  end

  -- Visual heading: the tank spins in place, the shooter and the carrier face
  -- their target (they back off and strafe, so their velocity would hide it),
  -- aiming kamikazes and snipers face their line, a stunned kamikaze spins,
  -- the rest face where they move.
  if self.type == "tank" then
    self.angle = self.angle + TANK_SPIN * dt
  elseif self.state == "stun" then
    self.angle = self.angle + self.def.stunSpin * dt
  else
    local want
    local t = self.target
    if self.state == "aim" then
      want = math.atan2(self.aimY, self.aimX)
    elseif (self.type == "shooter" or self.type == "carrier") and t then
      want = math.atan2(t.y - self.y, t.x - self.x)
    elseif self.vx ~= 0 or self.vy ~= 0 then
      want = math.atan2(self.vy, self.vx)
    end
    if want then self.angle = Util.angleLerp(self.angle, want, math.min(1, TURN_RATE * dt)) end
  end

  return true
end

-- Aplica dano; devolve true se morreu agora.
function Enemy:damage(amount)
  self.hp = self.hp - amount
  self.flash = Config.ENEMY_FLASH_TIME
  return self.hp <= 0
end

-- Empurrão (separação entre inimigos, knockback de bala).
function Enemy:push(dx, dy)
  self.x = self.x + dx
  self.y = self.y + dy
end

-- All enemy drawing lives here. The simpleSpace sprites are white, so the
-- type color is just the draw tint; the hit flash draws them untinted.
function Enemy:draw()
  local size = SIZE[self.type] or SIZE.grunt
  local c = self.flash > 0 and Config.COLORS.flash or self.color
  if self.materialize > 0 then
    -- Coming out of the door: noise dissolve with the door-warning red at
    -- the front (visual only: it already collides and can be shot).
    local k = 1 - self.materialize / Config.FX.dissolve.spawnTime
    if Shaders.dissolve(k, Config.COLORS.doorWarn) then
      love.graphics.setColor(c)
    else
      love.graphics.setColor(c[1], c[2], c[3], k)
    end
    Assets.draw(self.type, self.x, self.y, self.angle, size)
    Shaders.reset()
  else
    love.graphics.setColor(c)
    Assets.draw(self.type, self.x, self.y, self.angle, size)
  end

  -- HP bar (tank, carrier), only once it has taken damage.
  if self.def.hpBar and self.hp < self.def.hp then
    local w = size * 0.7
    UI.bar(self.color, self.x - w * 0.5, self.y + size * 0.5 + 1, w, self.hp / self.def.hp, 4)
  end
  self:drawHatches(1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Carrier hatches about to launch: two blinking door-warning lamps on its
-- sides for the last hatchTime s. `alphaMul` scales them (glow layer).
function Enemy:drawHatches(alphaMul)
  local def = self.def
  if not def.spawn or self.launchT >= def.hatchTime then return end
  if math.floor(self.launchT * 20) % 2 == 1 then return end
  local c = Config.COLORS.doorWarn
  local px, py = -math.sin(self.angle) * def.hatchOffset, math.cos(self.angle) * def.hatchOffset
  love.graphics.setColor(c[1], c[2], c[3], alphaMul)
  love.graphics.circle("fill", self.x + px, self.y + py, 2.5)
  love.graphics.circle("fill", self.x - px, self.y - py, 2.5)
end

-- Aim line (kamikaze, sniper): from the ship along the aim to the wall (at
-- most def.reach), in the door-warning red, growing stronger; once locked
-- it doubles in width and blinks. `alphaMul` scales it (glow layer).
function Enemy:drawTelegraph(alphaMul, arena)
  if self.state ~= "aim" then return end
  local def = self.def
  local dx, dy = self.aimX, self.aimY
  local t = def.reach
  if dx > 0 then t = math.min(t, (arena.x + arena.w - self.x) / dx)
  elseif dx < 0 then t = math.min(t, (arena.x - self.x) / dx) end
  if dy > 0 then t = math.min(t, (arena.y + arena.h - self.y) / dy)
  elseif dy < 0 then t = math.min(t, (arena.y - self.y) / dy) end
  local k = 1 - self.stateT / def.aimTime
  local a = def.lineAlpha * (0.4 + 0.6 * k)
  local w = def.lineWidth
  if self.stateT <= def.lockTime then
    a = math.floor(self.stateT * 40) % 2 == 0 and 1 or 0.6
    w = w * 2
  end
  local c = Config.COLORS.doorWarn
  local g = love.graphics
  g.setColor(c[1], c[2], c[3], a * alphaMul)
  g.setLineWidth(w)
  g.line(self.x, self.y, self.x + dx * t, self.y + dy * t)
  g.setLineWidth(1)
end

-- Shadow layer (src/post.lua): the silhouette, offset down-right.
function Enemy:drawShadow()
  if self.materialize > 0 then return end   -- no full shadow under a half-formed ship
  local size = SIZE[self.type] or SIZE.grunt
  local dx, dy = Post.shadowOffset(size)
  Assets.draw(self.type, self.x + dx, self.y + dy, self.angle, size)
end

-- Glow layer (src/post.lua): the white hit flash blooms a little.
function Enemy:drawGlow()
  self:drawHatches(Config.FX.emit.door)
  if self.flash <= 0 then return end
  love.graphics.setColor(1, 1, 1, Config.FX.emit.hitFlash)
  Assets.draw(self.type, self.x, self.y, self.angle, SIZE[self.type] or SIZE.grunt)
end

Enemy.BEHAVIORS = BEHAVIORS
return Enemy
