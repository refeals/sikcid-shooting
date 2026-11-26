-- Player options (the OPÇÕES screen), saved in love.filesystem like the
-- records: one "key=value" per line, tolerant of a missing or broken file
-- (anything unreadable falls back to its default, Config.OPTIONS.defaults).
--
-- Two copies of every value:
--   stored -- what the file holds (and what Options.save writes)
--   values -- what the game uses this session
-- They only differ for items a command line flag overrides (--fx, --mute,
-- --windowed, and the smoke test's own window and silence): the flag wins
-- for the session, the item is locked in the menu and the file keeps the
-- player's own choice. The smoke test and --media never read or write the
-- file: they run on the defaults.
--
-- Boot order (main.lua): Options.load() before the modules load (it sets
-- Config.FX.quality, which Post.load reads), Options.apply() after them.
-- At runtime the options screen calls Options.set(), which applies at once;
-- Options.save() writes the file when the screen closes.

local Config = require("src.config")

local O = Config.OPTIONS

local Options = {
  stored = {},
  values = {},
  locked = {},     -- key -> the flag shown next to a locked item ("--fx")
  dirty = false,   -- stored changed since the last save
  shakeMul = 1,    -- the shake level as a 0..1 multiplier (world:shake)
}

local KEYS = { "fx", "music", "sfx", "shake", "distortion", "fullscreen" }
local FX_LEVELS = { high = true, low = true, off = true }

-- The browser opens in a window (fullscreen needs a click there) and the
-- Batocera build is always fullscreen: only a PC gets the item.
function Options.hasFullscreen()
  return not Config.WEB and not Config.BATOCERA
end

local function defaultFx()
  local d = O.defaults.fx
  if d == "auto" or not FX_LEVELS[d] then return Config.WEB and "low" or "high" end
  return d
end

local function default(key)
  if key == "fx" then return defaultFx() end
  return O.defaults[key]
end

local function sanitizeVolume(v, key)
  v = tonumber(v)
  if not v or v ~= v then return default(key) end
  return math.max(0, math.min(O.volumeSteps, math.floor(v + 0.5)))
end

-- Snaps to the nearest shake level (Config.OPTIONS.shakeSteps).
local function sanitizeShake(v)
  v = tonumber(v)
  if not v or v ~= v then return default("shake") end
  local best, bestD = O.shakeSteps[#O.shakeSteps], math.huge
  for i = 1, #O.shakeSteps do
    local d = math.abs(O.shakeSteps[i] - v)
    if d < bestD then best, bestD = O.shakeSteps[i], d end
  end
  return best
end

local function sanitize(key, v)
  if key == "fx" then
    return FX_LEVELS[v] and v or defaultFx()
  elseif key == "music" or key == "sfx" then
    return sanitizeVolume(v, key)
  elseif key == "shake" then
    return sanitizeShake(v)
  elseif v == "1" or v == "0" then   -- distortion, fullscreen
    return v == "1"
  end
  return default(key)
end

local function readFile()
  local s = Options.stored
  if not love.filesystem.getInfo(O.file) then return end
  local ok, contents = pcall(love.filesystem.read, O.file)
  if not ok or not contents then return end
  for line in contents:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%w+)=(.+)$")
    if key and s[key] ~= nil then s[key] = sanitize(key, value) end
  end
end

function Options.load()
  local s, v, locked = Options.stored, Options.values, Options.locked
  for i = 1, #KEYS do s[KEYS[i]] = default(KEYS[i]) end
  if not (Config.SMOKE or Config.MEDIA) then readFile() end
  for i = 1, #KEYS do v[KEYS[i]] = s[KEYS[i]] end

  for k in pairs(locked) do locked[k] = nil end
  if Config.FX_FLAG then
    v.fx = FX_LEVELS[Config.FX_FLAG] and Config.FX_FLAG or defaultFx()
    locked.fx = "--fx"
  end
  if Config.MUTE then
    v.music, v.sfx = 0, 0
    local flag = Config.SMOKE and "--smoke" or "--mute"
    locked.music, locked.sfx = flag, flag
  end
  if Config.SMOKE or Config.WINDOWED then
    v.fullscreen = false
    locked.fullscreen = Config.SMOKE and "--smoke" or "--windowed"
  end
  Options.dirty = false

  -- Read by Post.load, which runs after this.
  Config.FX.quality = v.fx
  return v
end

-- Opens in a window instead of fullscreen? (main.lua, at boot)
function Options.startWindowed()
  return Config.SMOKE or Config.WINDOWED
    or (Options.hasFullscreen() and not Options.values.fullscreen)
end

local function applyKey(key)
  local v = Options.values[key]
  if key == "fx" then
    Config.FX.quality = v
    require("src.post").load()   -- new glow canvases and shaders for the level
  elseif key == "music" then
    require("src.music").setLevel(v / O.volumeSteps)
  elseif key == "sfx" then
    require("src.audio").setMaster(v / O.volumeSteps)
  elseif key == "shake" then
    Options.shakeMul = v / 100
  elseif key == "distortion" then
    require("src.post").setDistortion(v)
  elseif key == "fullscreen" then
    if Options.hasFullscreen() then love.window.setFullscreen(v, "desktop") end
  end
end

-- Applies everything the modules read at runtime (volumes, shake,
-- distortion). The FX level and the window were set up by the boot itself.
function Options.apply()
  applyKey("music")
  applyKey("sfx")
  applyKey("shake")
  applyKey("distortion")
end

-- Changes one item and applies it at once. Locked items don't change.
-- Returns whether the value changed.
function Options.set(key, value)
  if Options.locked[key] or Options.values[key] == value then return false end
  Options.values[key] = value
  Options.stored[key] = value
  Options.dirty = true
  applyKey(key)
  return true
end

-- Back to the defaults, except the items a flag holds this session.
function Options.restore()
  for i = 1, #KEYS do Options.set(KEYS[i], default(KEYS[i])) end
end

-- Writes the file if anything changed (never in the smoke test or --media).
function Options.save()
  if not Options.dirty then return true end
  Options.dirty = false
  if Config.SMOKE or Config.MEDIA then return true end
  local s = Options.stored
  local out = string.format("fx=%s\nmusic=%d\nsfx=%d\nshake=%d\ndistortion=%d\nfullscreen=%d\n",
    s.fx, s.music, s.sfx, s.shake, s.distortion and 1 or 0, s.fullscreen and 1 or 0)
  local ok, err = pcall(love.filesystem.write, O.file, out)
  if not ok then print("[options] could not write: " .. tostring(err)) end
  return ok
end

return Options
