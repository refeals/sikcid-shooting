-- Persistência do high score em love.filesystem.
-- Formato próprio "chave=valor" por linha: sem lib externa, tolerante a
-- arquivo ausente ou corrompido (volta a zero em vez de quebrar o jogo).

local Save = {
  FILE = "highscores.dat",
  data = { hs1 = 0, hs2 = 0 },  -- recorde de 1 jogador e de 2 jogadores
}

local function sanitize(v)
  v = tonumber(v)
  if not v or v ~= v or v < 0 then return 0 end   -- nil, NaN ou negativo
  return math.floor(v)
end

function Save.load()
  Save.data.hs1, Save.data.hs2 = 0, 0
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
  local out = string.format("hs1=%d\nhs2=%d\n", Save.data.hs1, Save.data.hs2)
  local ok, err = pcall(love.filesystem.write, Save.FILE, out)
  if not ok then print("[save] falha ao gravar: " .. tostring(err)) end
  return ok
end

-- Recorde do modo: 1 = um jogador, 2 = dois jogadores.
function Save.getHighScore(playerCount)
  return playerCount >= 2 and Save.data.hs2 or Save.data.hs1
end

-- Grava se for recorde. Devolve true quando bateu.
function Save.submit(playerCount, score)
  local key = playerCount >= 2 and "hs2" or "hs1"
  if score > Save.data[key] then
    Save.data[key] = math.floor(score)
    Save.write()
    return true
  end
  return false
end

return Save
