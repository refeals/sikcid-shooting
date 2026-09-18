-- Efeitos sonoros.
--
-- Cada som de Config.SFX é carregado de Config.AUDIO.dir .. "<id>.wav" (ou
-- .ogg). Som sem arquivo é ignorado em silêncio: o jogo roda igual, só mudo
-- naquele ponto.
--
-- Pool de vozes: cada som tem `voices` cópias da Source criadas no load e
-- usadas em rodízio. Nada é criado durante o jogo — o `clone()` por disparo
-- alocaria centenas de Sources por minuto com o tiro automático e estouraria
-- o limite de vozes do OpenAL em hardware modesto.

local Config = require("src.config")

local Audio = {
  enabled = false,   -- vira true se o módulo de áudio existir e algo carregar
  sounds = {},       -- id -> { voices = {Source...}, n, next, def, lastAt }
  loaded = 0,
  missing = 0,
  master = Config.AUDIO.master,
}

local EXTENSIONS = { ".wav", ".ogg" }

local function findFile(id)
  for i = 1, #EXTENSIONS do
    local path = Config.AUDIO.dir .. id .. EXTENSIONS[i]
    if love.filesystem.getInfo(path, "file") then return path end
  end
  return nil
end

function Audio.load()
  Audio.sounds = {}
  Audio.loaded, Audio.missing = 0, 0
  Audio.master = Config.AUDIO.master   -- já com --mute aplicado pelo main

  -- Sem módulo de áudio (desligado no conf ou sem dispositivo): tudo no-op.
  if not love.audio or not love.sound then
    print("[audio] modulo de audio indisponivel: sem som")
    return
  end

  for id, def in pairs(Config.SFX) do
    local path = findFile(id)
    if path then
      local ok, src = pcall(love.audio.newSource, path, "static")
      if ok and src then
        local n = math.max(1, def.voices or 1)
        local voices = { src }
        for v = 2, n do voices[v] = src:clone() end
        Audio.sounds[id] = { voices = voices, n = n, next = 1, def = def, lastAt = -math.huge }
        Audio.loaded = Audio.loaded + 1
      else
        print(string.format("[audio] falha ao carregar %s: %s", path, tostring(src)))
      end
    else
      Audio.missing = Audio.missing + 1
    end
  end

  Audio.enabled = Audio.loaded > 0
  print(string.format("[audio] %d som(ns) carregado(s), %d sem arquivo em %s",
    Audio.loaded, Audio.missing, Config.AUDIO.dir))
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

  local src = s.voices[s.next]
  s.next = s.next % s.n + 1

  local var = def.pitchVar or 0
  local p = (pitch or 1) * (1 + (math.random() * 2 - 1) * var)

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
