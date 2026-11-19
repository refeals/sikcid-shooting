-- Power-ups: definição (dados) e aplicação genérica.
--
-- Nenhum `if` de power-up espalhado pelo jogo. Cada definição só sabe
-- escrever na tabela de modificadores do jogador (`player.mods`), e o estado
-- é sempre RECALCULADO do zero:
--
--   mods base (Player:resetMods) -> apply() de cada power-up ativo
--
-- Assim não existe lógica de "reverter efeito" quando um expira: basta
-- recomputar. Adicionar um power-up novo = uma entrada em DEFS.

local Config = require("src.config")
local Util   = require("src.util")
local Audio  = require("src.audio")

local W = Config.WEAPON
local N = Config.POWERUPS   -- every number lives there

local Powerups = {}

-- weapon = true -> ocupa o "slot de arma" (substitui o anterior).
-- permanent = true -> efeito imediato, não entra na lista de ativos; o
-- grant recebe (player, world).
Powerups.DEFS = {
  {
    id = "spread", name = "SPREAD", letter = "S",
    desc = "3 tiros em leque",
    weapon = true, duration = N.spread.duration, weight = N.spread.weight,
    color = { 0.45, 0.85, 1.00, 1 },
    apply = function(m) m.weapon = "spread" end,
  },
  {
    id = "rapid", name = "RAPID FIRE", letter = "R",
    desc = "cadência de tiro em dobro",
    weapon = true, duration = N.rapid.duration, weight = N.rapid.weight,
    color = { 1.00, 0.85, 0.30, 1 },
    apply = function(m) m.fireRateMul = m.fireRateMul * N.rapid.fireMul end,
  },
  {
    id = "missiles", name = "MISSILES", letter = "M",
    desc = "mísseis teleguiados, dano 3",
    weapon = true, duration = N.missiles.duration, weight = N.missiles.weight,
    color = { 1.00, 0.55, 0.35, 1 },
    apply = function(m)
      m.weapon = "missiles"
      m.damage = W.missileDamage
    end,
  },
  {
    id = "boots", name = "SPEED BOOTS", letter = "V",
    desc = "40% mais velocidade",
    duration = N.boots.duration, weight = N.boots.weight,
    color = { 0.55, 1.00, 0.55, 1 },
    apply = function(m) m.speedMul = m.speedMul * N.boots.speedMul end,
  },
  {
    id = "bubble", name = "BOLHA", letter = "B",
    desc = "segura 1 golpe e empurra",
    duration = N.bubble.duration, weight = N.bubble.weight,
    color = { 0.60, 0.95, 1.00, 1 },
    apply = function(m) m.bubble = true end,
  },
  {
    id = "drone", name = "DRONE", letter = "D",
    desc = "drone que atira sozinho",
    duration = N.drone.duration, weight = N.drone.weight,
    color = { 0.75, 0.75, 1.00, 1 },
    apply = function(m) m.drone = true end,
  },
  {
    id = "damage", name = "DANO X2", letter = "X",
    desc = "dobra o dano de qualquer arma",
    duration = N.damage.duration, weight = N.damage.weight,
    color = { 1.00, 0.40, 0.30, 1 },
    apply = function(m) m.damageMul = m.damageMul * N.damage.mul end,
  },
  {
    id = "nova", name = "NOVA", letter = "N",
    desc = "onda de choque em volta (na hora)",
    sound = "nova",
    permanent = true, duration = 1, weight = N.nova.weight,
    color = { 1.00, 0.95, 0.60, 1 },
    grant = function(p, world)
      if world then world:nova(p) end
    end,
  },
  {
    id = "life", name = "EXTRA LIFE", letter = "+",
    desc = "+1 vida na hora (máx. 5)",
    sound = "pickup_life",    -- som próprio (os outros usam "pickup")
    permanent = true, duration = 1, weight = N.life.weight,
    color = { 1.00, 0.45, 0.55, 1 },
    grant = function(p)
      if p.lives < Config.PLAYER.maxLives then p.lives = p.lives + 1 end
    end,
  },
}

-- Sorteia uma definição por peso (Extra Life tem peso menor).
function Powerups.pick()
  return Util.weightedPick(Powerups.DEFS, #Powerups.DEFS)
end

-- Weapons only (the respawn support drop). A reused buffer: no allocation.
local weaponBuf, weaponCount = {}, 0
for i = 1, #Powerups.DEFS do
  if Powerups.DEFS[i].weapon then
    weaponCount = weaponCount + 1
    weaponBuf[weaponCount] = Powerups.DEFS[i]
  end
end

function Powerups.pickWeapon()
  return Util.weightedPick(weaponBuf, weaponCount)
end

function Powerups.byId(id)
  for i = 1, #Powerups.DEFS do
    if Powerups.DEFS[i].id == id then return Powerups.DEFS[i] end
  end
  return nil
end

-- Reconstrói player.mods a partir da lista de ativos.
function Powerups.recompute(player)
  player:resetMods()
  local list = player.powerups
  for i = 1, #list do
    local def = list[i].def
    if def.apply then def.apply(player.mods) end
  end
end

function Powerups.clear(player)
  local list = player.powerups
  for i = #list, 1, -1 do list[i] = nil end
  Powerups.recompute(player)
end

-- Removes the active power-up `id` (the bubble when it pops) and recomputes.
function Powerups.consume(player, id)
  local list = player.powerups
  for i = #list, 1, -1 do
    if list[i].def.id == id then
      list[i] = list[#list]
      list[#list] = nil
    end
  end
  Powerups.recompute(player)
end

-- Entrega um power-up ao jogador.
function Powerups.give(player, def, world)
  Audio.play(def.sound or "pickup")

  if def.permanent then
    if def.grant then def.grant(player, world) end
    return
  end

  local list = player.powerups

  -- Mesmo power-up de novo: só reseta o timer.
  for i = 1, #list do
    if list[i].def == def then
      list[i].timeLeft = def.duration
      return
    end
  end

  -- Power-up de arma substitui o de arma ativo; os outros acumulam.
  if def.weapon then
    for i = #list, 1, -1 do
      if list[i].def.weapon then
        list[i] = list[#list]
        list[#list] = nil
      end
    end
  end

  list[#list + 1] = { def = def, timeLeft = def.duration }
  Powerups.recompute(player)
end

function Powerups.update(dt, world)
  for pi = 1, world.playerCount do
    local player = world.players[pi]
    local list = player.powerups
    local expired = false
    local i = 1
    while i <= #list do
      local a = list[i]
      a.timeLeft = a.timeLeft - dt
      if a.timeLeft <= 0 then
        -- Swap-remove: a ordem dos ícones no HUD não importa.
        list[i] = list[#list]
        list[#list] = nil
        expired = true
      else
        i = i + 1
      end
    end
    if expired then
      Powerups.recompute(player)
      Audio.play("powerup_end")
    end
  end
end

return Powerups
