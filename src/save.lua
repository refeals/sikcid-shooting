-- Persistência dos recordes em love.filesystem.
-- Formato próprio "chave=valor" por linha: sem lib externa, tolerante a
-- arquivo ausente ou corrompido (volta a zero em vez de quebrar o jogo).
--
-- Três recordes:
--   solo -- melhor score individual numa partida de 1 jogador
--   duo  -- melhor score individual numa partida de 2 jogadores
--   coop -- melhor soma dos dois jogadores numa partida de 2 jogadores
--
-- E a cor escolhida no lobby por slot (color1/color2), como índice em
-- Config.PLAYER_PALETTE.

local Config = require("src.config")

local Save = {
  FILE = "highscores.dat",
  data = { solo = 0, duo = 0, coop = 0, color1 = 0, color2 = 0 },
}

local KEYS = { "solo", "duo", "coop" }

local function sanitize(v)
  v = tonumber(v)
  if not v or v ~= v or v < 0 then return 0 end   -- nil, NaN ou negativo
  return math.floor(v)
end

-- Palette index for slot `i`: anything out of range falls back to the default.
local function sanitizeColor(i, v)
  v = sanitize(v)
  if v < 1 or v > #Config.PLAYER_PALETTE then return Config.PLAYER_DEFAULT_COLOR[i] end
  return v
end

function Save.load()
  for i = 1, #KEYS do Save.data[KEYS[i]] = 0 end
  Save.data.color1 = Config.PLAYER_DEFAULT_COLOR[1]
  Save.data.color2 = Config.PLAYER_DEFAULT_COLOR[2]

  local info = love.filesystem.getInfo(Save.FILE)
  if not info then return Save.data end

  local ok, contents = pcall(love.filesystem.read, Save.FILE)
  if not ok or not contents then return Save.data end

  for line in contents:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%w+)=(.+)$")
    if key == "color1" or key == "color2" then
      Save.data[key] = sanitizeColor(key == "color1" and 1 or 2, value)
    elseif key and Save.data[key] ~= nil then
      Save.data[key] = sanitize(value)
    end
  end
  return Save.data
end

-- The smoke test never writes: its bots' scores (and its trip through
-- APAGAR RECORDES) stay in memory, away from the real records.
function Save.write()
  if Config.SMOKE then return true end
  local d = Save.data
  local out = string.format("solo=%d\nduo=%d\ncoop=%d\ncolor1=%d\ncolor2=%d\n",
    d.solo, d.duo, d.coop, d.color1, d.color2)
  local ok, err = pcall(love.filesystem.write, Save.FILE, out)
  if not ok then print("[save] falha ao gravar: " .. tostring(err)) end
  return ok
end

function Save.get(key)
  return Save.data[key] or 0
end

-- Stores the lobby color picks (palette indexes; c2 may be nil in 1 player).
-- Writes the file only when something changed. Smoke runs cycle colors on
-- purpose, so they never overwrite the real picks.
function Save.setColors(c1, c2)
  if Config.SMOKE then return end
  local d = Save.data
  local changed = false
  if c1 and c1 ~= d.color1 then d.color1 = c1; changed = true end
  if c2 and c2 ~= d.color2 then d.color2 = c2; changed = true end
  if changed then Save.write() end
end

-- OPÇÕES > APAGAR RECORDES: zeroes the records and writes the file. The
-- color picks stay.
function Save.clearRecords()
  for i = 1, #KEYS do Save.data[KEYS[i]] = 0 end
  return Save.write()
end

-- Registra o resultado de uma partida. Devolve uma tabela dizendo quais
-- recordes foram batidos (para o game over destacar).
-- `scores` = { scoreP1, scoreP2 } (scoreP2 pode ser nil em 1 jogador).
function Save.submitMatch(playerCount, scores)
  local beat = { solo = false, duo = false, coop = false }
  local s1 = math.floor(scores[1] or 0)

  if playerCount < 2 then
    if s1 > Save.data.solo then
      Save.data.solo = s1
      beat.solo = true
    end
  else
    local s2 = math.floor(scores[2] or 0)
    local best = s1 > s2 and s1 or s2
    if best > Save.data.duo then
      Save.data.duo = best
      beat.duo = true
    end
    if s1 + s2 > Save.data.coop then
      Save.data.coop = s1 + s2
      beat.coop = true
    end
  end

  if beat.solo or beat.duo or beat.coop then Save.write() end
  return beat
end

return Save
