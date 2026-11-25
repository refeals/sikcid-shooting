-- `love . --curve`: prints the wave curve to the console and quits, to tune
-- Config.WAVE, ENEMY_MIX, ELITE and BOSS without playing up to wave 40.
-- Per wave, for 1 and 2 players: total enemies, alive cap, s between
-- batches, elite chance and each type's share of the mix; boss waves show
-- the boss HP instead (and the adds' alive cap).

local Config = require("src.config")

local Curve = {}

local LAST_WAVE = 40

-- Short column names, in ENEMY_MIX order.
local SHORT = { grunt = "grn", runner = "run", shooter = "sht", tank = "tnk",
                kamikaze = "kmk", divisor = "div", sniper = "snp", carrier = "car" }

local function mixShares(w)
  local total = 0
  for i = 1, #Config.ENEMY_MIX do total = total + Config.mixWeight(Config.ENEMY_MIX[i], w) end
  local out = {}
  for i = 1, #Config.ENEMY_MIX do
    local v = Config.mixWeight(Config.ENEMY_MIX[i], w)
    out[i] = total > 0 and string.format("%3d", math.floor(v / total * 100 + 0.5)) or "  0"
  end
  return table.concat(out, " ")
end

function Curve.print()
  local names = {}
  for i = 1, #Config.ENEMY_MIX do names[i] = SHORT[Config.ENEMY_MIX[i].type] or "???" end
  print("wave | total 1p/2p | vivos 1p/2p | intervalo | elite | mix % (" .. table.concat(names, " ") .. ")")
  local B = Config.BOSS
  for w = 1, LAST_WAVE do
    if w % B.every == 0 then
      local n = w / B.every
      local hp = math.floor(Config.bossValue(B.hp, n))
      local adds = n >= B.adds.fromBoss and math.floor(Config.bossValue(B.adds.maxAlive, n)) or 0
      print(string.format("%4d | BOSS %d: vida %d (2p %d), extras vivos %d (2p %d)",
        w, n, hp, math.floor(hp * B.coopHp), adds,
        math.min(Config.MAX_ENEMIES, math.floor(adds * Config.WAVE.coopAlive))))
    else
      print(string.format("%4d | %5d %5d | %5d %5d | %9.2f | %4d%% | %s",
        w, Config.waveQuota(w, 1), Config.waveQuota(w, 2),
        Config.waveMaxAlive(w, 1), Config.waveMaxAlive(w, 2),
        Config.waveSpawnInterval(w), math.floor(Config.eliteChance(w) * 100 + 0.5), mixShares(w)))
    end
  end
  io.stdout:flush()
end

return Curve
