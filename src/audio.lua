-- Efeitos sonoros.
--
-- Duas origens por som de Config.SFX:
--   * `src` + `variants`: variações Kenney em Config.AUDIO.dir ..
--     "<src>_000.ogg", "_001"... Cada disparo sorteia uma variação diferente da
--     anterior (com o pitchVar por cima, o tiro automático não soa robótico).
--   * fallback: Config.AUDIO.dir .. "<id>.wav" (ou .ogg), o som sfxr gerado por
--     tools/gen_sfx.py. Usado quando o som não tem `src` ou quando nenhuma
--     variação carregou.
-- Som sem arquivo nenhum é ignorado em silêncio: o jogo roda igual, só mudo
-- naquele ponto.
--
-- Pool de vozes: cada arquivo carregado tem cópias da Source criadas no load e
-- usadas em rodízio. Nada é criado durante o jogo — o `clone()` por disparo
-- alocaria centenas de Sources por minuto com o tiro automático e estouraria
-- o limite de vozes do OpenAL em hardware modesto. Clones de uma Source
-- "static" dividem o mesmo buffer: mais vozes não gastam mais RAM de áudio.

local Config = require("src.config")

local Audio = {
  enabled = false,   -- vira true se o módulo de áudio existir e algo carregar
  -- id -> { pools = { {voices, n, next}... }, k, last, def, lastAt }
  sounds = {},
  loaded = 0,
  variants = 0,      -- variações Kenney carregadas (somando todos os sons)
  fallback = 0,      -- sons com `src` que caíram no arquivo sfxr
  missing = 0,
  master = 1,        -- sound effects volume (0..1), set by Options.apply
}

local EXTENSIONS = { ".wav", ".ogg" }

local function findFile(id)
  for i = 1, #EXTENSIONS do
    local path = Config.AUDIO.dir .. id .. EXTENSIONS[i]
    if love.filesystem.getInfo(path, "file") then return path end
  end
  return nil
end

-- One file -> one voice pool of `n` Sources (the original plus clones).
local function loadPool(path, n)
  local ok, src = pcall(love.audio.newSource, path, "static")
  if not ok or not src then
    print(string.format("[audio] falha ao carregar %s: %s", path, tostring(src)))
    return nil
  end
  local voices = { src }
  for v = 2, n do voices[v] = src:clone() end
  return { voices = voices, n = n, next = 1 }
end

-- Kenney variations of one sound. `voices` is the sound's total budget, split
-- across the variations (at least one voice each).
local function loadVariants(def, pools)
  local count = def.variants or 1
  local per = math.max(1, math.ceil((def.voices or 1) / count))
  for i = 0, count - 1 do
    local path = string.format("%s%s_%03d.ogg", Config.AUDIO.dir, def.src, i)
    if love.filesystem.getInfo(path, "file") then
      local pool = loadPool(path, per)
      if pool then pools[#pools + 1] = pool end
    end
  end
end

function Audio.load()
  Audio.sounds = {}
  Audio.loaded, Audio.variants, Audio.fallback, Audio.missing = 0, 0, 0, 0

  -- Sem módulo de áudio (desligado no conf ou sem dispositivo): tudo no-op.
  if not love.audio or not love.sound then
    print("[audio] modulo de audio indisponivel: sem som")
    return
  end

  local t0 = love.timer.getTime()
  for id, def in pairs(Config.SFX) do
    local pools = {}
    if def.src then
      loadVariants(def, pools)
      Audio.variants = Audio.variants + #pools
      if #pools == 0 then Audio.fallback = Audio.fallback + 1 end
    end
    if #pools == 0 then
      local path = findFile(id)
      local pool = path and loadPool(path, math.max(1, def.voices or 1))
      if pool then pools[1] = pool end
    end

    if #pools > 0 then
      Audio.sounds[id] = { pools = pools, k = #pools, last = 0, def = def, lastAt = -math.huge }
      Audio.loaded = Audio.loaded + 1
    else
      Audio.missing = Audio.missing + 1
    end
  end

  Audio.enabled = Audio.loaded > 0
  print(string.format("[audio] %d som(ns) carregado(s) (%d variacao(oes) Kenney), " ..
    "%d no fallback sfxr, %d sem arquivo em %s (%.0f ms)",
    Audio.loaded, Audio.variants, Audio.fallback, Audio.missing, Config.AUDIO.dir,
    (love.timer.getTime() - t0) * 1000))
end

-- Toca um som pelo id. `volume` e `pitch` são multiplicadores opcionais.
function Audio.play(id, volume, pitch)
  if not Audio.enabled then return end
  local s = Audio.sounds[id]
  if not s then return end

  -- Throttle: o mesmo som disparado várias vezes no mesmo instante (ex.: dez
  -- inimigos morrendo num frame) vira um só, em vez de estourar o volume.
  local now = love.timer.getTime()
  local def = s.def
  if now - s.lastAt < (def.minGap or 0) then return end
  s.lastAt = now

  -- Random variation, never the same one twice in a row.
  local k = s.k
  local pick = 1
  if k > 1 then
    if s.last == 0 then
      pick = math.random(k)
    else
      pick = math.random(k - 1)
      if pick >= s.last then pick = pick + 1 end
    end
    s.last = pick
  end

  local pool = s.pools[pick]
  local src = pool.voices[pool.next]
  pool.next = pool.next % pool.n + 1

  local var = def.pitchVar or 0
  local p = (def.pitch or 1) * (pitch or 1) * (1 + (math.random() * 2 - 1) * var)

  src:stop()
  src:setVolume((def.vol or 1) * (volume or 1) * Audio.master)
  src:setPitch(p)
  src:play()
end

function Audio.setMaster(v)
  Audio.master = v
end

function Audio.stopAll()
  if not Audio.enabled then return end
  love.audio.stop()
end

return Audio
