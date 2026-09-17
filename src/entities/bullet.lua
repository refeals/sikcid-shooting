-- Projétil. Vive em pool: nunca é criado nem descartado durante a partida,
-- só reinicializado por :reset().

local Config = require("src.config")

local Bullet = {}
Bullet.__index = Bullet

-- Objeto vazio para o pool (campos criados uma única vez).
function Bullet.new()
  return setmetatable({
    x = 0, y = 0, vx = 0, vy = 0,
    life = 0,
    dmg = 1,
    owner = 0,          -- 1 ou 2 = jogador; "enemy" = inimigo
    kind = "single",    -- "single" | "spread" | "missile" | "enemy"
    radius = Config.WEAPON.bulletRadius,
    angle = 0,
    color = Config.COLORS.bullet,
  }, Bullet)
end

function Bullet:reset(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  self.x, self.y = x, y
  self.vx, self.vy = dirX * speed, dirY * speed
  self.speed = speed
  self.life = life or Config.WEAPON.bulletLife
  self.dmg = dmg or 1
  self.owner = owner
  self.kind = kind or "single"
  self.radius = radius or Config.WEAPON.bulletRadius
  self.angle = math.atan2(dirY, dirX)
  self.color = color or (owner == "enemy" and Config.COLORS.bulletEnemy or Config.COLORS.bullet)
end

-- Devolve false quando a bala deve ser recolhida pelo pool.
function Bullet:update(dt, arena)
  self.life = self.life - dt
  if self.life <= 0 then return false end

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt

  local r = self.radius
  if self.x < arena.x - r or self.x > arena.x + arena.w + r
    or self.y < arena.y - r or self.y > arena.y + arena.h + r then
    return false
  end
  return true
end

-- Todo o desenho da bala mora aqui: trocar por sprite é mudança local.
function Bullet:draw()
  local c = self.color
  love.graphics.setColor(c)
  local r = self.radius
  if self.kind == "missile" then
    -- Míssil é um retângulo alongado na direção do movimento.
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.angle)
    love.graphics.rectangle("fill", -r * 2, -r * 0.6, r * 4, r * 1.2)
    love.graphics.pop()
  else
    love.graphics.rectangle("fill", self.x - r, self.y - r, r * 2, r * 2)
  end
end

return Bullet
