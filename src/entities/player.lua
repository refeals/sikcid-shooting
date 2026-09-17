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
    mods = {},
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
  end

  self.orbAngle = (self.orbAngle + W.orbSpeed * dt) % (math.pi * 2)
end

-- ---------------------------------------------------------------------------
-- Desenho: tudo do jogador mora aqui (trocar por sprite é mudança local).
-- ---------------------------------------------------------------------------
function Player:draw()
  if not self.alive then return end

  -- Pisca durante a invulnerabilidade.
  if self.invuln > 0 and math.floor(self.invuln * P.blinkRate) % 2 == 0 then
    return
  end

  local s, h = P.size, P.size * 0.5
  love.graphics.setColor(self.color)
  love.graphics.rectangle("fill", self.x - h, self.y - h, s, s)

  -- Marcador de mira: retângulo curto saindo do centro na direção atual.
  love.graphics.setColor(1, 1, 1, 0.9)
  local mx, my = self.x + self.aimX * (h + 4), self.y + self.aimY * (h + 4)
  love.graphics.rectangle("fill", mx - 2, my - 2, 4, 4)

  love.graphics.setColor(1, 1, 1, 1)
end

function Player:drawDebug()
  love.graphics.setColor(1, 0, 0, 0.6)
  love.graphics.circle("line", self.x, self.y, P.radius)
  love.graphics.setColor(1, 1, 1, 1)
end

Player.WEAPONS = WEAPONS
return Player
