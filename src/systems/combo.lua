-- Combo por jogador.
--
-- Cada morte soma +1 e reseta um timer de Config.COMBO.window. Se o timer
-- expirar, o combo volta a zero com um aviso visual. O multiplicador de
-- pontos é 1 + floor(combo / perMult), limitado a maxMult.
--
-- Os campos vivem no próprio jogador (combo, comboTimer, comboBest,
-- comboLost) para o HUD não precisar de outra tabela de lookup.

local Config = require("src.config")
local Audio  = require("src.audio")

local C = Config.COMBO

local Combo = {}

function Combo.reset(player)
  player.combo = 0
  player.comboTimer = 0
  player.comboBest = 0
  player.comboLost = 0     -- tempo restante do aviso "COMBO PERDIDO"
  player.comboPulse = 0    -- tempo restante do destaque do multiplicador
end

function Combo.add(player)
  local before = Combo.mult(player)
  player.combo = player.combo + 1
  player.comboTimer = C.window
  if player.combo > player.comboBest then player.comboBest = player.combo end
  -- Subiu de degrau: o HUD pisca o multiplicador.
  if Combo.mult(player) > before then
    player.comboPulse = C.pulseTime
    Audio.play("combo_up")
  end
end

function Combo.mult(player)
  local m = 1 + math.floor(player.combo / C.perMult)
  if m > C.maxMult then m = C.maxMult end
  return m
end

-- Fração restante do timer (0..1), para a barra encolhendo no HUD.
function Combo.fraction(player)
  if player.combo <= 0 then return 0 end
  return player.comboTimer / C.window
end

function Combo.update(dt, world)
  for i = 1, world.playerCount do
    local p = world.players[i]
    if p.comboLost > 0 then p.comboLost = p.comboLost - dt end
    if p.comboPulse > 0 then p.comboPulse = p.comboPulse - dt end
    if p.combo > 0 then
      p.comboTimer = p.comboTimer - dt
      if p.comboTimer <= 0 then
        p.combo = 0
        p.comboTimer = 0
        p.comboLost = C.lostMsgTime
        Audio.play("combo_lost")
      end
    end
  end
end

-- Morrer zera o combo na hora (sem aviso: o jogador já está vendo a morte).
function Combo.breakOn(player)
  if player.combo > 0 then
    player.combo = 0
    player.comboTimer = 0
    player.comboLost = C.lostMsgTime
  end
end

return Combo
