-- Persistência dos recordes em love.filesystem.
-- Formato próprio "chave=valor" por linha: sem lib externa, tolerante a
-- arquivo ausente ou corrompido (volta a zero em vez de quebrar o jogo).
--
-- Três recordes:
--   solo -- melhor score individual numa partida de 1 jogador
--   duo  -- melhor score individual numa partida de 2 jogadores
--   coop -- melhor soma dos dois jogadores numa partida de 2 jogadores

local Save = {
  FILE = "highscores.dat",
  data = { solo = 0, duo = 0, coop = 0 },
}

local KEYS = { "solo", "duo", "coop" }

local function sanitize(v)
  v = tonumber(v)
  if not v or v ~= v or v < 0 then return 0 end   -- nil, NaN ou negativo
  return math.floor(v)
end

function Save.load()
  for i = 1, #KEYS do Save.data[KEYS[i]] = 0 end

  local info = love.filesystem.getInfo(Save.FILE)
  if not info then return Save.data end

  local ok, contents = pcall(love.filesystem.read, Save.FILE)
  if not ok or not contents then return Save.data end

  for line in contents:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%w+)=(.+)$")
    if key and Save.data[key] ~= nil then
      Save.data[key] = sanitize(value)
    end
  end
  return Save.data
end

function Save.write()
  local out = string.format("solo=%d\nduo=%d\ncoop=%d\n",
    Save.data.solo, Save.data.duo, Save.data.coop)
  local ok, err = pcall(love.filesystem.write, Save.FILE, out)
  if not ok then print("[save] falha ao gravar: " .. tostring(err)) end
  return ok
end

function Save.get(key)
  return Save.data[key] or 0
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
