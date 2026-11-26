-- Background music: crossfade, ducked pause and fade out.
--
-- Screens ask for a ROLE (Music.play("menu"), Music.play("game")); each role
-- in Config.MUSIC.tracks is either:
--   * { file = "name" }                  one track, looped
--   * { playlist = { "a", "b", "c" } }   tracks played back to back
--     (a -> b -> c -> a ...), gapless
-- plus optional `gain` (0..1, per-role volume) and `fadeIn` (s, overrides
-- Config.MUSIC.fadeTime when the role comes in).
--
-- Single tracks are "stream" Sources (decoded a bit at a time, no 20 s of PCM
-- in RAM). Playlists are a QueueableSource fed by one Decoder per track: the
-- next track's first samples are queued right after the previous one's last
-- ones, so there is no gap. Every role restarts from its beginning (first
-- track of the playlist) once it has faded out completely.
--
-- Missing file = silence, no error (like the sound effects).

local Config = require("src.config")
local Util   = require("src.util")

local M = Config.MUSIC

local QUEUE_BUFFERS = 8   -- x 4096 samples ~ 0.74 s queued ahead

local Music = {
  roles = {},       -- role -> player (see newTrack / newPlaylist)
  current = nil,    -- role that should be audible
  duckOn = false,
  duckLevel = 1,    -- 1 = normal, M.duck = pause (interpolated)
}

local EXTENSIONS = { ".ogg", ".wav" }

local function findFile(name)
  for i = 1, #EXTENSIONS do
    local path = M.dir .. name .. EXTENSIONS[i]
    if love.filesystem.getInfo(path, "file") then return path end
  end
  print(string.format("[music] sem arquivo para '%s' em %s", name, M.dir))
  return nil
end

local function try(what, fn, ...)
  local ok, res = pcall(fn, ...)
  if ok and res then return res end
  print(string.format("[music] falha ao carregar %s: %s", what, tostring(res)))
  return nil
end

local function newTrack(def)
  local path = findFile(def.file)
  local src = path and try(path, love.audio.newSource, path, "stream")
  if not src then return nil end
  src:setLooping(true)
  return { src = src }
end

-- One Decoder per track, all with the same format (the QueueableSource has a
-- single sample rate / bit depth / channel count). Mismatches are skipped.
local function newPlaylist(def)
  local decoders = {}
  for _, name in ipairs(def.playlist) do
    local path = findFile(name)
    local d = path and try(path, love.sound.newDecoder, path)
    if d then
      local first = decoders[1]
      if first and (d:getSampleRate() ~= first:getSampleRate()
          or d:getBitDepth() ~= first:getBitDepth()
          or d:getChannelCount() ~= first:getChannelCount()) then
        print(string.format("[music] '%s' tem formato diferente do resto da playlist; ignorada", name))
      else
        decoders[#decoders + 1] = d
      end
    end
  end
  local d = decoders[1]
  if not d then return nil end
  local src = try("playlist", love.audio.newQueueableSource, d:getSampleRate(), d:getBitDepth(),
    d:getChannelCount(), QUEUE_BUFFERS)
  if not src then return nil end
  return { src = src, decoders = decoders, index = 1 }
end

-- Tops up the queue; at the end of a track, rewinds the next one and goes on.
local function feed(p)
  local src = p.src
  while src:getFreeBufferCount() > 0 do
    local sd = p.decoders[p.index]:decode()
    if not sd then
      p.index = p.index % #p.decoders + 1
      p.decoders[p.index]:seek(0)
      sd = p.decoders[p.index]:decode()
      if not sd then return end   -- empty file: give up this frame
    end
    src:queue(sd)
  end
  -- A long hitch can drain the queue, which stops the Source: resume.
  if not src:isPlaying() then src:play() end
end

function Music.load()
  Music.roles, Music.current = {}, nil
  Music.duckOn, Music.duckLevel = false, 1
  if not love.audio or not love.sound then return end

  local loaded = 0
  for role, def in pairs(M.tracks) do
    local p = def.playlist and newPlaylist(def) or newTrack(def)
    if p then
      p.vol = 0
      p.gain = def.gain or 1
      p.fadeIn = def.fadeIn or M.fadeTime
      Music.roles[role] = p
      loaded = loaded + 1
    end
  end
  print(string.format("[music] %d papel(eis) carregado(s)", loaded))
end

-- Switches to the role's music (crossfade). Same role still audible: keeps
-- playing where it is.
function Music.play(role)
  local p = Music.roles[role]
  if not p then return end
  Music.current = role
  if p.vol > 0 then return end
  -- Starts muted: the volume rises in Music.update (fade in), no click.
  p.src:setVolume(0)
  if p.decoders then
    p.index = 1
    p.decoders[1]:seek(0)
    feed(p)
  else
    p.src:play()
  end
end

-- Fades everything out (game over).
function Music.stop()
  Music.current = nil
end

-- Pause: lowers the music instead of stopping it.
function Music.duck(on)
  Music.duckOn = on and true or false
end

-- Pitch target (TEMPO LENTO pitches it down); eased in Music.update.
Music.pitch, Music.pitchTarget = 1, 1
local PITCH_EASE = 0.3   -- s for a full pitch swing

function Music.setPitch(p)
  Music.pitchTarget = p
end

-- Called every frame by main (pause included): runs the fades and keeps the
-- playlists fed.
function Music.update(dt)
  Music.duckLevel = Util.approach(Music.duckLevel, Music.duckOn and M.duck or 1, dt / M.fadeTime)
  local master = Config.AUDIO.master * M.volume * Music.duckLevel
  local pitchMoved = Music.pitch ~= Music.pitchTarget
  Music.pitch = Util.approach(Music.pitch, Music.pitchTarget, dt / PITCH_EASE)

  for role, p in pairs(Music.roles) do
    if pitchMoved then p.src:setPitch(Music.pitch) end
    local target = (role == Music.current) and 1 or 0
    local time = target > p.vol and p.fadeIn or M.fadeTime
    p.vol = Util.approach(p.vol, target, dt / time)
    if p.vol <= 0 then
      -- stop() rewinds a stream Source and empties a queue.
      if p.src:isPlaying() then p.src:stop() end
    else
      if p.decoders then feed(p) end
      p.src:setVolume(p.vol * p.gain * master)
    end
  end
end

return Music
