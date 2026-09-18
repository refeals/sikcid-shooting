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

local C = Config.COLORS
local W = Config.WEAPON
local PU = Config.POWERUP

local Powerups = {}

-- weapon = true -> ocupa o "slot de arma" (substitui o anterior).
-- permanent = true -> efeito imediato, não entra na lista de ativos.
Powerups.DEFS = {
  {
    id = "spread", name = "SPREAD", letter = "S",
    desc = "3 tiros em leque",
    weapon = true, duration = PU.duration, weight = 20,
    color = { 0.45, 0.85, 1.00, 1 },
    apply = function(m) m.weapon = "spread" end,
  },
  {
    id = "rapid", name = "RAPID FIRE", letter = "R",
    desc = "cadencia de tiro em dobro",
    weapon = true, duration = PU.duration, weight = 20,
    color = { 1.00, 0.85, 0.30, 1 },
    apply = function(m) m.fireRateMul = m.fireRateMul * 2 end,
  },
  {
    id = "missiles", name = "MISSILES", letter = "M",
    desc = "misseis teleguiados, dano 3",
    weapon = true, duration = PU.duration, weight = 15,
    color = { 1.00, 0.55, 0.35, 1 },
    apply = function(m)
      m.weapon = "missiles"
      m.damage = W.missileDamage
    end,
  },
  {
    id = "shield", name = "ORBITAL SHIELD", letter = "O",
    desc = "2 orbes que destroem ao tocar",
    duration = PU.duration, weight = 15,
    color = C.orb,
    apply = function(m) m.orbs = W.orbCount end,
  },
  {
    id = "boots", name = "SPEED BOOTS", letter = "V",
    desc = "40% mais velocidade",
    duration = PU.duration, weight = 20,
    color = { 0.55, 1.00, 0.55, 1 },
    apply = function(m) m.speedMul = m.speedMul * 1.4 end,
  },
  {
    id = "life", name = "EXTRA LIFE", letter = "+",
    desc = "+1 vida na hora (max. 5)",
    sound = "pickup_life",    -- som próprio (os outros usam "pickup")
    permanent = true, duration = 1, weight = 6,
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

-- Entrega um power-up ao jogador.
function Powerups.give(player, def)
  Audio.play(def.sound or "pickup")

  if def.permanent then
    if def.grant then def.grant(player) end
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
