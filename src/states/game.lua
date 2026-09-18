-- Tela 2: arena.
--
-- ETAPA 4: inimigos, colisão, morte, partículas, vidas/respawn/invulnerabilidade.
-- O spawn ainda é provisório (ver TEMP_SPAWN) e vira o sistema de waves na
-- etapa 5; combo, power-ups e game over entram nas etapas 6/7/8.

local Config   = require("src.config")
local Util     = require("src.util")
local State    = require("src.state")
local Screen   = require("src.screen")
local Pool     = require("src.pool")
local Hud      = require("src.hud")
local Audio    = require("src.audio")
local Save     = require("src.save")
local Combat   = require("src.systems.combat")
local Spawner  = require("src.systems.spawner")
local Combo    = require("src.systems.combo")
local Powerups = require("src.systems.powerups")
local Pickup   = require("src.entities.pickup")
local Player   = require("src.entities.player")
local Bullet   = require("src.entities.bullet")
local Enemy    = require("src.entities.enemy")
local Particle = require("src.entities.particle")

local Game = {}

local J = Config.JUICE

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
-- apenas limpos (nenhuma tabela é realocada durante o jogo).
local bullets   = Pool.new(Bullet.new, Config.MAX_BULLETS)
local enemies   = Pool.new(Enemy.new, Config.MAX_ENEMIES)
local particles = Pool.new(Particle.new, Config.MAX_PARTICLES)
local pickups   = Pool.new(Pickup.new, Config.MAX_PICKUPS)

local world = {
  arena = arena,
  bullets = bullets,
  enemies = enemies,
  particles = particles,
  pickups = pickups,
  players = {},
  playerCount = 0,
  godMode = false,
}

-- ---------------------------------------------------------------------------
-- Serviços que as entidades e os sistemas consomem
-- ---------------------------------------------------------------------------
function world:spawnBullet(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  local b = self.bullets:acquire()
  if not b then return nil end
  b:reset(x, y, dirX, dirY, speed, dmg, owner, kind, life, radius, color)
  return b
end

function world:spawnEnemy(kind, x, y)
  local e = self.enemies:acquire()
  if not e then return nil end
  e:reset(kind, x, y)
  return e
end

function world:nearestPlayer(x, y)
  local best, bestD2 = nil, math.huge
  for i = 1, self.playerCount do
    local p = self.players[i]
    if p.alive then
      local d2 = Util.dist2(x, y, p.x, p.y)
      if d2 < bestD2 then best, bestD2 = p, d2 end
    end
  end
  return best
end

-- Inimigo mais próximo dentro de `maxR` (usa o grid da broadphase, então é
-- barato mesmo com um punhado de mísseis voando).
function world:nearestEnemy(x, y, maxR)
  local best, bestD2 = nil, maxR * maxR
  Combat.queryCircle(x, y, maxR, function(e)
    if e.dead then return end
    local d2 = Util.dist2(x, y, e.x, e.y)
    if d2 < bestD2 then best, bestD2 = e, d2 end
  end)
  return best
end

function world:randomPlayer()
  local alive, n = nil, 0
  for i = 1, self.playerCount do
    local p = self.players[i]
    if p.alive then
      n = n + 1
      if math.random(n) == 1 then alive = p end   -- reservoir sampling
    end
  end
  return alive
end

-- Respawna se o parceiro estiver vivo (ou se ele já estiver fora de vez, caso
-- em que a partida segue com um jogador só).
function world:canRespawn(player)
  if self.playerCount == 1 then return true end
  local other = self.players[player.index == 1 and 2 or 1]
  if not other or other.alive or other.out then return true end
  -- Parceiro também caído: espera ele voltar, mas no máximo 0.5s a mais,
  -- senão os dois ficariam presos esperando um pelo outro.
  return player.respawnTimer <= -0.5
end

function world:addScore(playerIndex, points)
  local p = self.players[playerIndex]
  if p then p.score = p.score + points end
end

-- Atalho para efeitos soltarem partículas sem conhecer o pool.
function world:burst(count, x, y, color, size)
  Particle.burst(self.particles, count, x, y, color, size)
end

function world:shake(mag)
  if mag > self.shakeMag then self.shakeMag = mag end
end

function world:hitStop(t)
  if t > self.hitStopTimer then self.hitStopTimer = t end
end

function world:onEnemyKilled(enemy, killerIndex)
  local count = enemy.type == "tank" and J.tankDeathParticles or J.deathParticles
  Particle.burst(self.particles, count, enemy.x, enemy.y, enemy.color, enemy.def.size * 0.35)

  -- Combo sobe primeiro: a morte já conta com o multiplicador novo.
  if type(killerIndex) == "number" then
    local killer = self.players[killerIndex]
    if killer then
      Combo.add(killer)
      self:addScore(killerIndex, enemy.def.points * Combo.mult(killer))
    end
  end

  self:dropPowerup(enemy.x, enemy.y, false)

  if enemy.type == "tank" then
    self:shake(J.shakeTankDeath)
    self:hitStop(J.hitStopTank)
    Audio.play("tank_die")
  else
    self:shake(J.shakeEnemyDeath)
  end

  if Config.SMOKE then require("src.smoke").bump("kills") end
end

function world:onPlayerHit(player)
  player.alive = false
  player.lives = player.lives - 1
  Combo.breakOn(player)
  Particle.burst(self.particles, J.playerDeathParticles, player.x, player.y, player.color, 5)
  self:shake(J.shakePlayerDeath)
  Audio.play("player_die")

  if player.lives <= 0 then
    player.lives = 0
    player.out = true
  else
    player.respawnTimer = Config.PLAYER.respawnTime
  end

  if Config.SMOKE then require("src.smoke").bump("deaths") end
end

-- Resumo da partida, reaproveitado (nenhuma tabela nova no fim do jogo).
local summary = {
  playerCount = 0,
  scores = {}, combos = {}, devices = {},
  wave = 1, wavesCleared = 0,
  beat = { solo = false, duo = false, coop = false },
}

function world:onGameOver()
  summary.playerCount = self.playerCount
  for i = 1, self.playerCount do
    local p = self.players[i]
    summary.scores[i] = p.score
    summary.combos[i] = p.comboBest
    summary.devices[i] = p.device
  end
  summary.wave = Spawner.wave
  -- A wave em andamento não conta como sobrevivida.
  summary.wavesCleared = math.max(0, Spawner.wave - 1)

  local beat = Save.submitMatch(self.playerCount, summary.scores)
  summary.beat.solo, summary.beat.duo, summary.beat.coop = beat.solo, beat.duo, beat.coop

  State.switch(require("src.states.gameover"), summary)
end

-- Solta um power-up. `guaranteed` = drop de fim de wave (sempre sai); senão
-- passa pelo sorteio de Config.POWERUP.dropChance.
function world:dropPowerup(x, y, guaranteed)
  if not guaranteed and math.random() > Config.POWERUP.dropChance then return end
  local def = Powerups.pick()
  if not def then return end
  local p = self.pickups:acquire()
  if not p then return end
  p:reset(x, y, def)
  return p
end

-- ---------------------------------------------------------------------------
local showHitboxes = false
local hudInfo = { title = "", subtitle = "" }   -- reaproveitado todo frame

function Game:enter(devices, count)
  world.playerCount = count or 1
  world.players = {}
  world.shakeMag = 0
  world.hitStopTimer = 0
  world.godMode = Config.SMOKE_GOD or false
  bullets:clear()
  enemies:clear()
  particles:clear()
  pickups:clear()
  Spawner.load(arena)
  Spawner.reset(world, Config.SMOKE_WAVE)

  for i = 1, world.playerCount do
    local p = Player.new(i, devices[i])
    local dx = world.playerCount == 1 and 0 or (i == 1 and -30 or 30)
    p:spawn(arena.cx + dx, arena.cy)
    Combo.reset(p)
    world.players[i] = p
  end

  if Config.SMOKE then
    require("src.smoke").note("state", "game/" .. world.playerCount .. "p")
  end
end

local function allPlayersOut()
  for i = 1, world.playerCount do
    if not world.players[i].out then return false end
  end
  return true
end

function Game:update(dt)
  for i = 1, world.playerCount do
    local d = world.players[i].device
    -- Controle de um jogador caiu: pausa até ele voltar.
    if d and not d.connected then
      State.push(require("src.states.pause"), world, "waiting", i)
      return
    end
    -- START e BACK abrem a pausa. Sair da partida só pelo menu de pausa
    -- (com confirmação): um toque em SELECT não pode jogar o jogador fora.
    if d and d.connected and (d:pressed("start") or
      (d:pressed("back") and not d:isDown("start"))) then
      State.push(require("src.states.pause"), world, "paused")
      return
    end
  end

  -- Hit-stop: congela a simulação por alguns frames (o desenho continua).
  if world.hitStopTimer > 0 then
    world.hitStopTimer = world.hitStopTimer - dt
    return
  end

  Spawner.update(dt, world)

  -- Grid montado antes das entidades: os mísseis consultam o inimigo mais
  -- próximo por ele (Combat.update remonta depois do movimento).
  Combat.buildGrid(enemies)

  for i = 1, world.playerCount do
    world.players[i]:update(dt, world)
  end

  for i = 1, enemies.count do
    enemies.items[i]:update(dt, world)
  end

  -- Balas: swap-remove pelo pool, sem table.remove.
  local i = 1
  while i <= bullets.count do
    if bullets.items[i]:update(dt, world) then i = i + 1 else bullets:release(i) end
  end

  i = 1
  while i <= particles.count do
    if particles.items[i]:update(dt) then i = i + 1 else particles:release(i) end
  end

  -- Pickups: expiram sozinhos e são coletados por contato (poucos vivos,
  -- então o teste direto contra os jogadores é mais barato que usar o grid).
  i = 1
  while i <= pickups.count do
    local pk = pickups.items[i]
    local taken = false
    if pk:update(dt) then
      local r = Config.POWERUP.pickupRadius + Config.PLAYER.radius
      for pi = 1, world.playerCount do
        local p = world.players[pi]
        if p.alive and Util.dist2(pk.x, pk.y, p.x, p.y) <= r * r then
          Powerups.give(p, pk.def)
          Particle.burst(particles, 6, pk.x, pk.y, pk.def.color, 4)
          if Config.SMOKE then require("src.smoke").bump("pickups") end
          taken = true
          break
        end
      end
    else
      taken = true
    end
    if taken then pickups:release(i) else i = i + 1 end
  end

  -- No respiro entre waves os timers de power-up e combo ficam parados: não
  -- há inimigos, então correr o relógio só desperdiçaria o power-up e
  -- tornaria impossível carregar o combo para a próxima wave.
  local resting = Spawner.isResting()
  if not resting then Powerups.update(dt, world) end

  Combat.update(dt, world)
  Combo.update(dt, world, resting)

  -- Screen shake: decai rápido e é aplicado no canvas inteiro.
  if world.shakeMag > 0 then
    world.shakeMag = Util.approach(world.shakeMag, 0, J.shakeDecay * dt)
    Screen.setShake(Util.randRange(-world.shakeMag, world.shakeMag),
                    Util.randRange(-world.shakeMag, world.shakeMag))
  else
    Screen.setShake(0, 0)
  end

  if allPlayersOut() then
    world:onGameOver()
    return
  end

  if Config.SMOKE then
    local Smoke = require("src.smoke")
    Smoke.max("peakBullets", bullets.peak)
    Smoke.max("peakEnemies", enemies.peak)
    Smoke.max("peakParticles", particles.peak)
    for i2 = 1, world.playerCount do Smoke.max("combo", world.players[i2].comboBest) end
    Smoke.note("denied", bullets.denied + enemies.denied + particles.denied)
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

  love.graphics.setColor(C.arenaLine)
  love.graphics.rectangle("line", arena.x + 0.5, arena.y + 0.5, arena.w - 1, arena.h - 1)

  Spawner.draw()

  for i = 1, pickups.count do pickups.items[i]:draw() end
  for i = 1, particles.count do particles.items[i]:draw() end
  for i = 1, enemies.count do enemies.items[i]:draw() end
  for i = 1, bullets.count do bullets.items[i]:draw() end
  for i = 1, world.playerCount do world.players[i]:draw() end

  -- Banner "WAVE N" no começo da wave, sumindo aos poucos.
  if Spawner.banner > 0 then
    local t = Spawner.banner / Config.WAVE.bannerTime
    love.graphics.setColor(C.text[1], C.text[2], C.text[3], math.min(1, t * 2))
    love.graphics.printf(string.format("WAVE %d", Spawner.wave),
      arena.cx - 120, arena.cy - 60 - (1 - t) * 10, 240, "center")
  end

  -- Aviso de wave completa durante o respiro.
  if Spawner.isResting() and Spawner.wave >= 1 then
    love.graphics.setColor(C.textWarn)
    love.graphics.printf(string.format("WAVE %d COMPLETA", Spawner.wave),
      arena.cx - 120, arena.cy - 50, 240, "center")
    love.graphics.setColor(C.textDim)
    love.graphics.printf(string.format("BONUS %d   -   PROXIMA EM %.1f",
      Spawner.wave * Config.WAVE.clearBonus, math.max(0, Spawner.timer)),
      arena.cx - 120, arena.cy - 34, 240, "center")
  end

  -- Contagem regressiva do respawn.
  for i = 1, world.playerCount do
    local p = world.players[i]
    if not p.alive and not p.out then
      love.graphics.setColor(p.color)
      love.graphics.printf(string.format("P%d VOLTA EM %.1f", p.index, math.max(0, p.respawnTimer)),
        arena.cx - 80, arena.cy - 30 + (i - 1) * 16, 160, "center")
    end
  end

  if showHitboxes then
    love.graphics.setColor(1, 0, 0, 0.6)
    for i = 1, enemies.count do
      local e = enemies.items[i]
      love.graphics.circle("line", e.x, e.y, e.radius)
    end
    for i = 1, bullets.count do
      local b = bullets.items[i]
      love.graphics.circle("line", b.x, b.y, b.radius)
    end
    for i = 1, world.playerCount do world.players[i]:drawDebug() end
  end

  hudInfo.title = string.format("WAVE %d", math.max(1, Spawner.wave))
  hudInfo.subtitle = Spawner.isResting()
    and string.format("PROXIMA EM %.1f", math.max(0, Spawner.timer))
    or string.format("INIMIGOS %d", Spawner.remaining(world))
  Hud.draw(world.players, world.playerCount, hudInfo)

  if Config.DEBUG then
    love.graphics.setColor(C.textDim)
    love.graphics.print(string.format("FPS %d  in %d  bal %d  par %d  neg %d%s",
      love.timer.getFPS(), enemies.count, bullets.count, particles.count,
      bullets.denied + enemies.denied + particles.denied,
      world.godMode and "  [GOD]" or ""),
      4, Config.VIRTUAL_H - 14)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Game:keypressed(key)
  if not Config.DEBUG then return end
  if key == "f1" then
    showHitboxes = not showHitboxes
  elseif key == "f2" then
    Spawner.skipWave(world)
  elseif key == "f3" then
    world.godMode = not world.godMode
  elseif key == "f4" then
    -- Dropa um power-up aleatório no centro.
    world:dropPowerup(arena.cx, arena.cy, true)
  end
end

Game.world = world
return Game
