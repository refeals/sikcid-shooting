-- Colisões, dano, separação entre inimigos e limpeza dos pools.
--
-- Broadphase: grid uniforme de células de Config.GRID_CELL px. Com 150
-- inimigos, testar todos os pares seria ~11k testes por frame; o grid derruba
-- para algumas dezenas. As células são buffers reaproveitados: nenhuma tabela
-- é criada durante a partida.
--
-- Narrowphase: círculos com distância ao quadrado (sem sqrt).

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")

local Combat = {}

local CELL = Config.GRID_CELL
local ORIGIN_Y = Config.HUD_H
local COLS = math.ceil(Config.VIRTUAL_W / CELL)
local ROWS = math.ceil((Config.VIRTUAL_H - Config.HUD_H) / CELL)

-- cells[i] = { count = n, [1..n] = enemy }
local cells = {}
for i = 1, COLS * ROWS do cells[i] = { count = 0 } end

local function cellIndex(x, y)
  local cx = math.floor(x / CELL)
  local cy = math.floor((y - ORIGIN_Y) / CELL)
  if cx < 0 then cx = 0 elseif cx >= COLS then cx = COLS - 1 end
  if cy < 0 then cy = 0 elseif cy >= ROWS then cy = ROWS - 1 end
  return cy * COLS + cx + 1, cx, cy
end

local function buildGrid(enemies)
  for i = 1, COLS * ROWS do cells[i].count = 0 end
  for i = 1, enemies.count do
    local e = enemies.items[i]
    e.dead = false
    local idx = cellIndex(e.x, e.y)
    local c = cells[idx]
    local n = c.count + 1
    c.count = n
    c[n] = e
  end
end

-- Percorre as células que cobrem o círculo (x, y, r) chamando fn(enemy).
-- `fn` devolve false para interromper a varredura.
local function queryCircle(x, y, r, fn)
  local _, cx, cy = cellIndex(x, y)
  local span = math.ceil(r / CELL)
  for gy = cy - span, cy + span do
    if gy >= 0 and gy < ROWS then
      for gx = cx - span, cx + span do
        if gx >= 0 and gx < COLS then
          local c = cells[gy * COLS + gx + 1]
          for i = 1, c.count do
            if fn(c[i]) == false then return end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Overlap fix: no two enemy SPRITES overlap (each one's `space` is half its
-- drawn size). The gentle spacing is steering in src/entities/enemy.lua; this
-- is the hard limit behind it. Each enemy of an overlapping pair moves out by
-- its share of the overlap, inversely to its mass (def.push: the tank shoves
-- the small ones aside); the pair is seen from both sides, so the overlap is
-- gone in one frame. The boss is an obstacle that is never pushed. The query
-- callback is module-level (fed by upvalues): no closure per enemy.
-- ---------------------------------------------------------------------------
local SP = Config.ENEMY_SPACING
local GOLDEN = 2.39996       -- rad: spreads enemies stacked on the same spot
local ovSelf, ovMass, ovIndex = nil, 1, 0

local function pushApart(b)
  local a = ovSelf
  if b == a or b.dead then return end
  local minDist = a.space + b.space
  local dx, dy = a.x - b.x, a.y - b.y
  local d2 = dx * dx + dy * dy
  if d2 >= minDist * minDist then return end
  local bm = b.def.push or 1
  local share = bm / (ovMass + bm)
  if d2 <= 0.0001 then
    -- Same spot (a batch from one door): split along a per-enemy angle.
    local ang = ovIndex * GOLDEN
    a:push(math.cos(ang) * minDist * share, math.sin(ang) * minDist * share)
    return
  end
  local d = math.sqrt(d2)
  local k = (minDist - d) * share / d
  a:push(dx * k, dy * k)
end

local function resolveOverlaps(world)
  local enemies, arena = world.enemies, world.arena
  local boss = world.boss
  local bossSolid = boss and (boss.state == "enter" or boss.state == "fight")
  local bossSpace = bossSolid and boss.size * SP.bossFrac or 0
  for i = 1, enemies.count do
    local a = enemies.items[i]
    ovSelf, ovMass, ovIndex = a, a.def.push or 1, i
    queryCircle(a.x, a.y, a.space + SP.maxSpace, pushApart)

    if bossSolid then
      local minDist = a.space + bossSpace
      local dx, dy = a.x - boss.x, a.y - boss.y
      local d2 = dx * dx + dy * dy
      if d2 < minDist * minDist and d2 > 0.0001 then
        local d = math.sqrt(d2)
        local k = (minDist - d) / d
        a:push(dx * k, dy * k)
      end
    end

    -- Never shoved through a wall (same clamp as Enemy:update).
    local r = a.radius
    if a.x < arena.x + r then a.x = arena.x + r end
    if a.x > arena.x + arena.w - r then a.x = arena.x + arena.w - r end
    if a.y < arena.y + r then a.y = arena.y + r end
    if a.y > arena.y + arena.h - r then a.y = arena.y + arena.h - r end
  end
  ovSelf = nil
end

-- ---------------------------------------------------------------------------
-- Balas dos jogadores contra inimigos.
-- ---------------------------------------------------------------------------
local function bulletsVsEnemies(world)
  local bullets = world.bullets
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" and not b.dead then
      queryCircle(b.x, b.y, b.radius + 16, function(e)
        if e.dead then return end
        local rr = b.radius + e.radius
        if Util.dist2(b.x, b.y, e.x, e.y) > rr * rr then return end

        b.dead = true
        local killed = e:damage(b.dmg)
        -- O som de morte fica em world:onEnemyKilled (cobre bala e orbe).
        if not killed then Audio.play("enemy_hit") end
        if killed then
          e.dead = true
          world:onEnemyKilled(e, b.owner)
        else
          -- Knockback leve na direção do tiro.
          local nx, ny = Util.normalize(b.vx, b.vy)
          local mass = e.def.push or 1
          e:push(nx * Config.ENEMY_KNOCKBACK / mass * 0.02,
                 ny * Config.ENEMY_KNOCKBACK / mass * 0.02)
        end
        return false   -- a bala para no primeiro inimigo
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Boss: outside the grid (see src/entities/boss.lua), so it is tested
-- directly: one circle against every player bullet.
-- ---------------------------------------------------------------------------
local function bulletsVsBoss(world)
  local boss = world.boss
  if not boss or not boss:isFighting() then return end
  local bullets = world.bullets
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" and not b.dead then
      local rr = b.radius + boss.radius
      if Util.dist2(b.x, b.y, boss.x, boss.y) <= rr * rr then
        b.dead = true
        world:burst(2, b.x, b.y, boss.variant.color, 3)
        if boss:hit(b.dmg, b.owner, world) then return end
      end
    end
  end
end

-- Player bullets against the boss's homing missiles. The missiles are
-- gathered first into a reused buffer (there are only a few of them).
local missileBuf, missileCount = {}, 0

local function bulletsVsBossMissiles(world)
  local bullets = world.bullets
  missileCount = 0
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.kind == "bossMissile" and not b.dead then
      missileCount = missileCount + 1
      missileBuf[missileCount] = b
    end
  end
  if missileCount == 0 then return end

  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" and not b.dead then
      for k = 1, missileCount do
        local m = missileBuf[k]
        if not m.dead then
          local rr = b.radius + m.radius
          if Util.dist2(b.x, b.y, m.x, m.y) <= rr * rr then
            b.dead = true
            m.hp = m.hp - b.dmg
            if m.hp <= 0 then
              m.dead = true
              m:blast(world)
              world:addScore(b.owner, Config.BOSS.missile.points)
            else
              world:burst(2, m.x, m.y, m.color, 3)
            end
            break
          end
        end
      end
    end
  end
  for k = 1, missileCount do missileBuf[k] = nil end
end

-- ---------------------------------------------------------------------------
-- Contato inimigo x jogador e balas de inimigo x jogador.
-- ---------------------------------------------------------------------------
local function enemiesVsPlayers(world)
  local P = Config.PLAYER
  -- Touching the boss kills too, also while it slides in (the ALERTA banner
  -- warned about it); not once it is blowing up.
  local boss = world.boss
  local bossSolid = boss and (boss.state == "enter" or boss.state == "fight")
  for pi = 1, world.playerCount do
    local p = world.players[pi]
    if p.alive and p.invuln <= 0 and not world.godMode then
      queryCircle(p.x, p.y, P.radius + 24, function(e)
        if e.dead then return end
        local rr = P.radius + e.radius
        if Util.dist2(p.x, p.y, e.x, e.y) > rr * rr then return end
        world:onPlayerHit(p)
        return false
      end)
      if p.alive and bossSolid then
        local rr = P.radius + boss.radius
        if Util.dist2(p.x, p.y, boss.x, boss.y) <= rr * rr then world:onPlayerHit(p) end
      end
    end
  end
end

local function enemyBulletsVsPlayers(world)
  local P = Config.PLAYER
  local bullets = world.bullets
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner == "enemy" and not b.dead then
      for pi = 1, world.playerCount do
        local p = world.players[pi]
        if p.alive and p.invuln <= 0 and not world.godMode then
          local rr = P.radius + b.radius
          if Util.dist2(b.x, b.y, p.x, p.y) <= rr * rr then
            b.dead = true
            world:onPlayerHit(p)
            break
          end
        end
      end
    end
  end
end

-- Orbes do power-up Orbital Shield (ativado na etapa 7; o teste é barato).
local function orbsVsEnemies(world)
  local W = Config.WEAPON
  local boss = world.boss
  for pi = 1, world.playerCount do
    local p = world.players[pi]
    if p.alive and p.mods.orbs > 0 then
      for oi = 1, p.mods.orbs do
        local a = p.orbAngle + (oi - 1) * (math.pi * 2 / p.mods.orbs)
        local ox = p.x + math.cos(a) * W.orbDistance
        local oy = p.y + math.sin(a) * W.orbDistance
        queryCircle(ox, oy, W.orbRadius + 16, function(e)
          if e.dead or e.orbHit > 0 then return end
          local rr = W.orbRadius + e.radius
          if Util.dist2(ox, oy, e.x, e.y) > rr * rr then return end
          e.orbHit = W.orbHitCooldown
          if e:damage(W.orbDamage) then
            e.dead = true
            world:onEnemyKilled(e, p.index)
          end
        end)
        if boss and boss:isFighting() and boss.orbHit <= 0 then
          local rr = W.orbRadius + boss.radius
          if Util.dist2(ox, oy, boss.x, boss.y) <= rr * rr then
            boss.orbHit = W.orbHitCooldown
            boss:hit(W.orbDamage, p.index, world)
          end
        end
      end
    end
  end
end

-- Recolhe para os pools tudo que morreu neste frame (swap-remove).
local function sweep(world)
  local enemies, bullets = world.enemies, world.bullets
  local i = 1
  while i <= enemies.count do
    if enemies.items[i].dead then enemies:release(i) else i = i + 1 end
  end
  i = 1
  while i <= bullets.count do
    if bullets.items[i].dead then bullets:release(i) else i = i + 1 end
  end
end

function Combat.update(dt, world)
  buildGrid(world.enemies)
  resolveOverlaps(world)
  bulletsVsEnemies(world)
  bulletsVsBossMissiles(world)
  bulletsVsBoss(world)
  orbsVsEnemies(world)
  enemiesVsPlayers(world)
  enemyBulletsVsPlayers(world)
  sweep(world)
end

-- Exposto para o spawner escolher um ponto livre e para debug.
Combat.queryCircle = queryCircle
Combat.buildGrid = buildGrid

return Combat
