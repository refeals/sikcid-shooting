-- Records, machine stats and lobby colors in love.filesystem.
-- Own "key=value" format, one per line: no external lib, tolerant of a
-- missing or corrupted file (falls back to zero instead of breaking the
-- game). Keys the file lacks (an older file) stay at zero; keys it has that
-- the game no longer knows are ignored.
--
-- Records (only a match that reached the game over counts):
--   solo     -- best single score in a 1 player match
--   duo      -- best single score in a 2 player match
--   coop     -- best sum of both players in a 2 player match
--   waveSolo -- furthest wave reached in a 1 player match
--   waveDuo  -- furthest wave reached in a 2 player match
--   combo    -- longest kill chain (Player.comboBest), any mode
--
-- Machine stats (every match, quit ones included; see Save.addPlayed):
--   matches, kills (anything a player shot down), bosses, subbosses,
--   seconds (match time, no pauses)
--
-- And the color picked in the lobby per slot (color1/color2), as an index
-- into Config.PLAYER_PALETTE.

local Config = require("src.config")

local Save = {
  FILE = "highscores.dat",
  data = {
    solo = 0, duo = 0, coop = 0, waveSolo = 0, waveDuo = 0, combo = 0,
    matches = 0, kills = 0, bosses = 0, subbosses = 0, seconds = 0,
    color1 = 0, color2 = 0,
  },
}

-- Everything APAGAR RECORDES zeroes, in file order (colors go last).
local KEYS = { "solo", "duo", "coop", "waveSolo", "waveDuo", "combo",
               "matches", "kills", "bosses", "subbosses", "seconds" }

local function sanitize(v)
  v = tonumber(v)
  if not v or v ~= v or v < 0 or v == math.huge then return 0 end   -- nil, NaN, negative, inf
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

-- The smoke test never writes: its bots' scores and stats (and its trip
-- through APAGAR RECORDES) stay in memory, away from the real records.
function Save.write()
  if Config.SMOKE then return true end
  local d = Save.data
  local parts = {}
  for i = 1, #KEYS do parts[i] = string.format("%s=%d\n", KEYS[i], d[KEYS[i]]) end
  parts[#parts + 1] = string.format("color1=%d\ncolor2=%d\n", d.color1, d.color2)
  local ok, err = pcall(love.filesystem.write, Save.FILE, table.concat(parts))
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

-- OPÇÕES > APAGAR RECORDES: zeroes the records and the machine stats and
-- writes the file. The color picks stay.
function Save.clearRecords()
  for i = 1, #KEYS do Save.data[KEYS[i]] = 0 end
  return Save.write()
end

-- Raises `key` to `v` if it is a new best; true when it was.
local function best(key, v)
  v = math.floor(v or 0)
  if v > Save.data[key] then
    Save.data[key] = v
    return true
  end
  return false
end

-- A match reached the game over: records it. Returns a table saying which
-- score records fell (for the results screen to highlight).
-- `scores` = { scoreP1, scoreP2 } (scoreP2 may be nil in 1 player); `wave`
-- = the wave reached; `combo` = the longest kill chain of the match.
local beat = { solo = false, duo = false, coop = false }
function Save.submitMatch(playerCount, scores, wave, combo)
  beat.solo, beat.duo, beat.coop = false, false, false
  local s1 = math.floor(scores[1] or 0)
  local other

  if playerCount < 2 then
    beat.solo = best("solo", s1)
    other = best("waveSolo", wave)
  else
    local s2 = math.floor(scores[2] or 0)
    beat.duo = best("duo", s1 > s2 and s1 or s2)
    beat.coop = best("coop", s1 + s2)
    other = best("waveDuo", wave)
  end
  other = best("combo", combo) or other

  if beat.solo or beat.duo or beat.coop or other then Save.write() end
  return beat
end

-- A match ended, whatever the way (game over, quit from the pause, game
-- closed): adds it to the machine stats and writes the file.
function Save.addPlayed(kills, bosses, subbosses, seconds)
  local d = Save.data
  d.matches = d.matches + 1
  d.kills = d.kills + math.floor(kills or 0)
  d.bosses = d.bosses + math.floor(bosses or 0)
  d.subbosses = d.subbosses + math.floor(subbosses or 0)
  d.seconds = d.seconds + math.floor((seconds or 0) + 0.5)
  return Save.write()
end

return Save
