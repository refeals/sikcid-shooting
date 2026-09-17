-- Tela 2: arena.
--
-- ETAPA 3: jogadores se movem, colidem com as paredes e atiram; balas em
-- pool. Inimigos, waves, combo e power-ups entram nas etapas 4+.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")
local Pool   = require("src.pool")
local Hud    = require("src.hud")
local Player = require("src.entities.player")
local Bullet = require("src.entities.bullet")

local Game = {}

-- Arena = tela inteira menos a faixa de HUD no topo.
local arena = {
  x = 0,
  y = Config.HUD_H,
  w = Config.VIRTUAL_W,
  h = Config.VIRTUAL_H - Config.HUD_H,
}
arena.cx = arena.x + arena.w * 0.5
arena.cy = arena.y + arena.h * 0.5

-- Pools criados uma única vez no carregamento do módulo; entre partidas são
-- apenas limpos (nenhuma tabela é realocada).
local bullets = Pool.new(Bullet.new, Config.MAX_BULLETS)

local world = {
  arena = arena,
  bullets = bullets,
  players = {},
  playerCount = 0,
}

function world:spawnBullet(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  local b = self.bullets:acquire()
  if not b then return nil end
  b:reset(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  return b
end

-- ETAPA 4 sobrescreve com a regra real (só respawna se o parceiro vive).
function world:canRespawn(player) -- luacheck: ignore
  return true
end

local showHitboxes = false

-- ---------------------------------------------------------------------------
function Game:enter(devices, count)
  world.playerCount = count or 1
  world.players = {}
  bullets:clear()

  for i = 1, world.playerCount do
    local p = Player.new(i, devices[i])
    -- Dois jogadores nascem lado a lado no centro.
    local dx = world.playerCount == 1 and 0 or (i == 1 and -30 or 30)
    p:spawn(arena.cx + dx, arena.cy)
    world.players[i] = p
  end

  if Config.SMOKE then
    require("src.smoke").note("state", "game/" .. world.playerCount .. "p")
  end
end

function Game:update(dt)
  -- Saída pelo BACK de qualquer jogador (START junto é o combo de sair).
  for i = 1, world.playerCount do
    local d = world.players[i].device
    if d and d.connected and d:pressed("back") and not d:isDown("start") then
      State.switch(require("src.states.lobby"))
      return
    end
  end

  for i = 1, world.playerCount do
    world.players[i]:update(dt, world)
  end

  -- Balas: swap-remove pelo pool, sem table.remove.
  local i = 1
  while i <= bullets.count do
    if bullets.items[i]:update(dt, arena) then
      i = i + 1
    else
      bullets:release(i)
    end
  end

  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.max("peakBullets", bullets.peak)
    Smoke.note("denied", bullets.denied)
  end
end

-- ---------------------------------------------------------------------------
function Game:draw()
  local C = Config.COLORS

  love.graphics.setColor(C.arenaBg)
  love.graphics.rectangle("fill", arena.x, arena.y, arena.w, arena.h)

  -- Grade sutil: dá referência de escala e movimento sem custo de textura.
  love.graphics.setColor(C.arenaLine[1], C.arenaLine[2], C.arenaLine[3], 0.45)
  for gx = arena.x + 40, arena.x + arena.w - 1, 40 do
    love.graphics.line(gx + 0.5, arena.y, gx + 0.5, arena.y + arena.h)
  end
  for gy = arena.y + 40, arena.y + arena.h - 1, 40 do
    love.graphics.line(arena.x, gy + 0.5, arena.x + arena.w, gy + 0.5)
  end

  -- Paredes.
  love.graphics.setColor(C.arenaLine)
  love.graphics.rectangle("line", arena.x + 0.5, arena.y + 0.5, arena.w - 1, arena.h - 1)

  for bi = 1, bullets.count do bullets.items[bi]:draw() end
  for pi = 1, world.playerCount do world.players[pi]:draw() end

  if showHitboxes then
    for bi = 1, bullets.count do
      local b = bullets.items[bi]
      love.graphics.setColor(1, 0, 0, 0.6)
      love.graphics.circle("line", b.x, b.y, b.radius)
    end
    for pi = 1, world.playerCount do world.players[pi]:drawDebug() end
  end

  Hud.draw(world.players, world.playerCount, nil)

  if Config.DEBUG then
    love.graphics.setColor(C.textDim)
    love.graphics.print(string.format("FPS %d  balas %d/%d  neg %d",
      love.timer.getFPS(), bullets.count, bullets.capacity, bullets.denied),
      4, Config.VIRTUAL_H - 14)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Game:keypressed(key)
  if not Config.DEBUG then return end
  if key == "f1" then showHitboxes = not showHitboxes end
end

Game.world = world
return Game
