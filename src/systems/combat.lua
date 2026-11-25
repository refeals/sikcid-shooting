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
local X2_COLOR = Config.POWERUPS.damage.color   -- DANO X2 hit sparks
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
  -- `dead` is NOT reset here (Enemy:reset does that): enemies killed outside
  -- the collision pass (NOVA, salvo blasts) stay flagged until the sweep.
  for i = 1, enemies.count do
    local e = enemies.items[i]
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
  if b == a or b.dead or b.phasing then return end
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
    -- A charging kamikaze (`phasing`) neither shoves nor is shoved.
    if not a.phasing then
      ovSelf, ovMass, ovIndex = a, a.def.push or 1, i
      queryCircle(a.x, a.y, a.space + SP.maxSpace, pushApart)
    end

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
        if e.dead or e == b.lastHit then return end
        local rr = b.radius + e.radius
        if Util.dist2(b.x, b.y, e.x, e.y) > rr * rr then return end

        -- PERFURANTE: the shot goes on through `pierce` more enemies (never
        -- the same one twice in a row).
        if b.pierce > 0 then
          b.pierce = b.pierce - 1
          b.lastHit = e
        else
          b.dead = true
        end
        local killed = e:damage(b.dmg)
        -- O som de morte fica em world:onEnemyKilled (cobre bala e explosão).
        -- A hit that doesn't kill: sparks bouncing back in the shot's color
        -- (DANO X2: its color and a deeper hit sound). A kill has its
        -- explosion instead.
        if not killed then
          world:impact(b.x, b.y, b.vx, b.vy, b.powered and X2_COLOR or b.color)
          if b.powered then Audio.play("enemy_hit", 1.2, 0.75) else Audio.play("enemy_hit") end
        end
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
        -- Respawn salvo: the blast hurts everything around the hit.
        if b.kind == "salvo" then world:salvoBlast(b) end
        return false   -- one enemy per shot per frame
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Boss: outside the grid (see src/entities/boss.lua), so it is tested
-- directly: one circle against every player bullet.
-- ---------------------------------------------------------------------------

-- While sliding in, the boss's shield blocks player shots: they die on its
-- surface (no damage) and a salvo goes off there.
local function bulletsVsBossShield(world, boss)
  local R = boss:shieldRadius()
  local bullets = world.bullets
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" and not b.dead then
      local rr = b.radius + R
      local dx, dy = b.x - boss.x, b.y - boss.y
      local d2 = dx * dx + dy * dy
      if d2 <= rr * rr then
        b.dead = true
        local d = math.sqrt(d2)
        if d > 0.0001 then
          boss:shieldHit(boss.x + dx / d * R, boss.y + dy / d * R, world)
        else
          boss:shieldHit(b.x, b.y, world)
        end
        if b.kind == "salvo" then world:salvoBlast(b) end
      end
    end
  end
end

local function bulletsVsBoss(world)
  local boss = world.boss
  if not boss then return end
  if boss:hasShield() then
    bulletsVsBossShield(world, boss)
    return
  end
  if not boss:isFighting() then return end
  local bullets = world.bullets
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner ~= "enemy" and not b.dead then
      local rr = b.radius + boss.radius
      if Util.dist2(b.x, b.y, boss.x, boss.y) <= rr * rr then
        b.dead = true
        world:impact(b.x, b.y, b.vx, b.vy, b.powered and X2_COLOR or b.color)
        local killed = boss:hit(b.dmg, b.owner, world)
        if b.kind == "salvo" then world:salvoBlast(b) end
        if killed or not boss:isFighting() then return end
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
    -- Salvo missiles fly past them to their targets.
    if b.owner ~= "enemy" and b.kind ~= "salvo" and not b.dead then
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
    -- Mid-dash (burst + grace) the ship passes through everything. Right
    -- after it, a ship still inside an enemy lingers protected while it keeps
    -- touching one (Player:updateDash spends the linger budget).
    if p.alive and p.invuln <= 0 and p.dashSafe <= 0 and not world.godMode then
      queryCircle(p.x, p.y, P.radius + 24, function(e)
        -- Fresh divisor fragments fly out harmless for a moment.
        if e.dead or e.harmless > 0 then return end
        local rr = P.radius + e.radius
        if Util.dist2(p.x, p.y, e.x, e.y) > rr * rr then return end
        if p.dashLingering then
          p.dashTouched = true
        else
          world:onPlayerHit(p, e.type)
        end
        return false
      end)
      if p.alive and bossSolid then
        local rr = P.radius + boss.radius
        if Util.dist2(p.x, p.y, boss.x, boss.y) <= rr * rr then
          if p.dashLingering then
            p.dashTouched = true
          else
            world:onPlayerHit(p, "boss")
          end
        end
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
        -- Dashing ships let shots through (the shot keeps flying).
        if p.alive and p.invuln <= 0 and not p:dashGuarded() and not world.godMode then
          local rr = P.radius + b.radius
          if Util.dist2(b.x, b.y, p.x, p.y) <= rr * rr then
            b.dead = true
            world:onPlayerHit(p, b.src or b.kind)
            break
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

function Combat.update(_, world)
  buildGrid(world.enemies)
  resolveOverlaps(world)
  bulletsVsEnemies(world)
  bulletsVsBossMissiles(world)
  bulletsVsBoss(world)
  enemiesVsPlayers(world)
  enemyBulletsVsPlayers(world)
  sweep(world)
end

-- Exposto para o spawner escolher um ponto livre e para debug.
Combat.queryCircle = queryCircle
Combat.buildGrid = buildGrid

return Combat
