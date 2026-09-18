-- Jogador. Não é pooled: existem no máximo 2 instâncias, criadas no início
-- da partida. Lê input SÓ do seu device (self.device).

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")

local P = Config.PLAYER
local W = Config.WEAPON

local Player = {}
Player.__index = Player

-- Armas disponíveis, indexadas por mods.weapon. As etapas seguintes só
-- acrescentam entradas aqui; nada de `if` espalhado pelo update.
local WEAPONS = {}

WEAPONS.single = function(self, world)
  world:spawnBullet(self.x, self.y, self.aimX, self.aimY,
    W.bulletSpeed, self.mods.damage, self.index, "single")
  Audio.play("shot")
end

-- Spread: leque de W.spreadCount balas cobrindo W.spreadAngle.
WEAPONS.spread = function(self, world)
  local base = math.atan2(self.aimY, self.aimX)
  local n = W.spreadCount
  local step = n > 1 and (W.spreadAngle / (n - 1)) or 0
  local start = base - W.spreadAngle * 0.5
  for i = 1, n do
    local a = start + step * (i - 1)
    world:spawnBullet(self.x, self.y, math.cos(a), math.sin(a),
      W.bulletSpeed, self.mods.damage, self.index, "spread")
  end
  Audio.play("shot_spread")
end

-- Missiles: projétil lento que corrige a rota até o inimigo mais próximo.
WEAPONS.missiles = function(self, world)
  world:spawnBullet(self.x, self.y, self.aimX, self.aimY,
    W.missileSpeed, self.mods.damage, self.index, "missile",
    W.bulletLife * 2, W.bulletRadius + 1)
  Audio.play("shot_missile")
end

function Player.new(index, device)
  local self = setmetatable({
    index = index,
    device = device,
    color = index == 1 and Config.COLORS.p1 or Config.COLORS.p2,
    x = 0, y = 0,
    vx = 0, vy = 0,
    aimX = 0, aimY = -1,      -- mira inicial: para cima
    lives = P.lives,
    score = 0,
    alive = true,
    out = false,              -- zerou as vidas: fica de fora até o fim
    invuln = 0,
    respawnTimer = 0,
    fireCooldown = 0,
    orbAngle = 0,
    muzzle = 0,               -- clarão curto do cano ao atirar
    spawnFx = 0,              -- anel de respawn
    mods = {},
    powerups = {},            -- { { def = <DEF>, timeLeft = s }, ... }
  }, Player)
  self:resetMods()
  return self
end

-- Valores base da arma/movimento. Os power-ups reaplicam por cima disto.
function Player:resetMods()
  local m = self.mods
  m.speedMul = 1
  m.fireRateMul = 1
  m.damage = W.damage
  m.weapon = "single"
  m.orbs = 0
end

function Player:spawn(x, y)
  self.x, self.y = x, y
  self.vx, self.vy = 0, 0
  self.alive = true
  self.invuln = P.invulnTime
  self.respawnTimer = 0
  self.fireCooldown = 0
  self.aimX, self.aimY = 0, -1
  self.muzzle = 0
  self.spawnFx = P.spawnFxTime
  Audio.play("player_spawn")
  -- Morrer custa os power-ups temporários.
  require("src.systems.powerups").clear(self)
end

-- ---------------------------------------------------------------------------
-- Mira: analógico direito > d-pad > direção do movimento > última mira válida.
-- Devolve também se o jogador está "mirando de propósito" (para AUTO_FIRE
-- desligado).
-- ---------------------------------------------------------------------------
function Player:updateAim(moveX, moveY)
  local d = self.device
  local aiming = false

  local ax, ay = d:aimVector()
  if ax ~= 0 or ay ~= 0 then
    aiming = true
  else
    ax, ay = d:dpadVector()
    if ax ~= 0 or ay ~= 0 then aiming = true end
  end

  if aiming then
    local nx, ny = Util.normalize(ax, ay)
    self.aimX, self.aimY = nx, ny
  elseif moveX ~= 0 or moveY ~= 0 then
    -- Sem mira explícita: segue o movimento, mas não vira "última mira".
    local nx, ny = Util.normalize(moveX, moveY)
    self.aimX, self.aimY = nx, ny
  end
  -- Caso contrário mantém self.aimX/aimY (última mira válida).

  return aiming
end

function Player:update(dt, world)
  if self.invuln > 0 then self.invuln = self.invuln - dt end
  if self.muzzle > 0 then self.muzzle = self.muzzle - dt end
  if self.spawnFx > 0 then self.spawnFx = self.spawnFx - dt end

  if not self.alive then
    if self.out then return end
    self.respawnTimer = self.respawnTimer - dt
    if self.respawnTimer <= 0 and world:canRespawn(self) then
      self:spawn(world.arena.cx, world.arena.cy)
    end
    return
  end

  local d = self.device
  local moveX, moveY = 0, 0
  if d.connected then moveX, moveY = d:moveVector() end

  -- Movimento com aceleração alta (resposta imediata, sem patinar).
  local speed = P.speed * self.mods.speedMul
  local targetX, targetY = moveX * speed, moveY * speed
  local step = P.accel * dt
  self.vx = Util.approach(self.vx, targetX, step)
  self.vy = Util.approach(self.vy, targetY, step)

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  -- Paredes da arena.
  local a, r = world.arena, P.radius
  if self.x < a.x + r then self.x, self.vx = a.x + r, 0 end
  if self.x > a.x + a.w - r then self.x, self.vx = a.x + a.w - r, 0 end
  if self.y < a.y + r then self.y, self.vy = a.y + r, 0 end
  if self.y > a.y + a.h - r then self.y, self.vy = a.y + a.h - r, 0 end

  local aiming = self:updateAim(moveX, moveY)

  -- Tiro automático.
  if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end
  local wantsFire = Config.AUTO_FIRE_ALWAYS or aiming
  if wantsFire and self.fireCooldown <= 0 then
    local fn = WEAPONS[self.mods.weapon] or WEAPONS.single
    fn(self, world)
    self.fireCooldown = 1 / (W.fireRate * self.mods.fireRateMul)
    self.muzzle = P.muzzleTime
  end

  self.orbAngle = (self.orbAngle + W.orbSpeed * dt) % (math.pi * 2)
end

-- ---------------------------------------------------------------------------
-- Desenho: tudo do jogador mora aqui (trocar por sprite é mudança local).
-- ---------------------------------------------------------------------------
function Player:draw()
  if not self.alive then return end

  -- Anel de respawn: quadrado que encolhe até o tamanho do jogador.
  if self.spawnFx > 0 then
    local t = self.spawnFx / P.spawnFxTime
    local r = P.size * 0.5 + 18 * t
    love.graphics.setColor(self.color[1], self.color[2], self.color[3], t)
    love.graphics.rectangle("line", self.x - r, self.y - r, r * 2, r * 2)
  end

  -- Pisca durante a invulnerabilidade.
  if self.invuln > 0 and math.floor(self.invuln * P.blinkRate) % 2 == 0 then
    return
  end

  local s, h = P.size, P.size * 0.5
  love.graphics.setColor(self.color)
  love.graphics.rectangle("fill", self.x - h, self.y - h, s, s)

  -- Orbes do Orbital Shield (a colisão deles fica em systems/combat.lua).
  local orbs = self.mods.orbs
  if orbs > 0 then
    love.graphics.setColor(Config.COLORS.orb)
    for i = 1, orbs do
      local a = self.orbAngle + (i - 1) * (math.pi * 2 / orbs)
      love.graphics.circle("fill",
        self.x + math.cos(a) * W.orbDistance,
        self.y + math.sin(a) * W.orbDistance, W.orbRadius)
    end
  end

  -- Marcador de mira: retângulo curto saindo do centro na direção atual.
  -- Cresce por um instante a cada tiro (clarão do cano).
  local flash = self.muzzle > 0
  love.graphics.setColor(1, 1, 1, flash and 1 or 0.9)
  local mx, my = self.x + self.aimX * (h + 4), self.y + self.aimY * (h + 4)
  local ms = flash and 3 or 2
  love.graphics.rectangle("fill", mx - ms, my - ms, ms * 2, ms * 2)

  love.graphics.setColor(1, 1, 1, 1)
end

function Player:drawDebug()
  love.graphics.setColor(1, 0, 0, 0.6)
  love.graphics.circle("line", self.x, self.y, P.radius)
  love.graphics.setColor(1, 1, 1, 1)
end

Player.WEAPONS = WEAPONS
return Player
