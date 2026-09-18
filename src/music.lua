-- Música de fundo com crossfade, pausa "abafada" e fade out.
--
-- As telas pedem um papel (Music.play("menu"), Music.play("game")); o papel
-- aponta para uma faixa em Config.MUSIC.tracks. Se o papel novo cai na mesma
-- faixa que já está tocando, nada reinicia.
--
-- Faixas em modo "stream": decodificadas aos poucos, sem carregar 80s de áudio
-- na RAM. Arquivo ausente = silêncio, sem erro (como os efeitos).

local Config = require("src.config")
local Util   = require("src.util")

local M = Config.MUSIC

local Music = {
  tracks = {},      -- nome -> { src = Source, vol = 0..1 (fade atual) }
  current = nil,    -- nome da faixa que deve estar audível
  duckOn = false,
  duckLevel = 1,    -- 1 = normal, M.duck = pausa (interpolado)
}

local EXTENSIONS = { ".ogg", ".wav" }

local function findFile(name)
  for i = 1, #EXTENSIONS do
    local path = M.dir .. name .. EXTENSIONS[i]
    if love.filesystem.getInfo(path, "file") then return path end
  end
  return nil
end

function Music.load()
  Music.tracks, Music.current = {}, nil
  Music.duckOn, Music.duckLevel = false, 1
  if not love.audio or not love.sound then return end

  -- Uma Source por faixa distinta (dois papéis na mesma faixa dividem).
  local loaded = 0
  for _, name in pairs(M.tracks) do
    if not Music.tracks[name] then
      local path = findFile(name)
      if path then
        local ok, src = pcall(love.audio.newSource, path, "stream")
        if ok and src then
          src:setLooping(true)
          Music.tracks[name] = { src = src, vol = 0 }
          loaded = loaded + 1
        else
          print(string.format("[music] falha ao carregar %s: %s", path, tostring(src)))
        end
      else
        print(string.format("[music] sem arquivo para '%s' em %s", name, M.dir))
      end
    end
  end
  print(string.format("[music] %d faixa(s) carregada(s)", loaded))
end

-- Troca para a faixa do papel pedido (crossfade). Mesma faixa: só garante que
-- está tocando.
function Music.play(role)
  local name = M.tracks[role]
  if not name then return end
  local t = Music.tracks[name]
  if not t then return end
  Music.current = name
  if not t.src:isPlaying() then
    -- Começa mudo: o volume sobe no Music.update (fade in), sem estalo.
    t.src:setVolume(0)
    t.src:play()
  end
end

-- Fade out de tudo (game over).
function Music.stop()
  Music.current = nil
end

-- Pausa: abaixa a música em vez de parar.
function Music.duck(on)
  Music.duckOn = on and true or false
end

-- Chamado todo frame pelo main (inclusive em pausa): anda os fades.
function Music.update(dt)
  local step = dt / M.fadeTime
  Music.duckLevel = Util.approach(Music.duckLevel, Music.duckOn and M.duck or 1, step)
  local master = Config.AUDIO.master * M.volume * Music.duckLevel

  for name, t in pairs(Music.tracks) do
    local target = (name == Music.current) and 1 or 0
    t.vol = Util.approach(t.vol, target, step)
    if t.vol <= 0 then
      if t.src:isPlaying() then t.src:stop() end   -- stop() volta ao início
    else
      t.src:setVolume(t.vol * master)
    end
  end
end

return Music
