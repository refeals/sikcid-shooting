-- Run log: one CSV line per wave and one per match, appended to runs.csv in
-- the LÖVE save folder (next to highscores.dat). It is the data for tuning
-- the wave curve (Config.WAVE, ENEMY_MIX, ELITE, BOSS): how long each wave
-- takes, who dies to what, how far runs get and with which upgrades.
--
-- Columns:
--   tipo      -- "wave", "wave_fatal" (the wave the match ended in) or "partida"
--   partida   -- match id (start date and time)
--   data      -- start date
--   jogadores -- 1 or 2
--   wave      -- the wave (the last one reached, on "partida")
--   boss      -- 1 on boss waves
--   segundos  -- game time of the wave (of the whole match, on "partida");
--                pauses and overlay screens don't count
--   mortes    -- deaths in the wave (in the whole match, on "partida")
--   causas    -- "P1:kamikaze|P2:sniper" (on "partida": the last death)
--   vidas     -- lives per player as the wave ended ("3|2")
--   upgrades  -- "P1:pierce2 cadence1|P2:..." (id + level, in pick order)
--   pontos    -- score of all players together
--   motivo    -- "partida" only: "fim" (game over) or "abandono" (quit)
--
-- Off in the smoke run, so bots never mix with real players' data.

local Config = require("src.config")

local RunLog = {}

-- --smokelog: the smoke run logs too, into its own file (never the real one).
local FILE = Config.SMOKE_LOG and "runs-smoke.csv" or "runs.csv"
local HEADER = "tipo,partida,data,jogadores,wave,boss,segundos,mortes,causas,vidas,upgrades,pontos,motivo\n"

local S = {
  on = false, finished = true, world = nil,
  id = "", date = "", total = 0,
  wave = 0, waveT = 0, deaths = 0, runDeaths = 0,
  causes = {}, lastCause = "",
}

local function write(line)
  pcall(function()
    if not love.filesystem.getInfo(FILE, "file") then
      love.filesystem.write(FILE, HEADER)
    end
    love.filesystem.append(FILE, line)
  end)
end

local function lives(world)
  local parts = {}
  for i = 1, world.playerCount do parts[i] = tostring(world.players[i].lives) end
  return table.concat(parts, "|")
end

local function upgrades(world)
  local parts = {}
  for i = 1, world.playerCount do
    local p = world.players[i]
    local list = {}
    for k = 1, #p.upgradeOrder do
      local id = p.upgradeOrder[k]
      list[k] = id .. (p.upgrades[id] or 1)
    end
    parts[i] = "P" .. i .. ":" .. table.concat(list, " ")
  end
  return table.concat(parts, "|")
end

local function score(world)
  local s = 0
  for i = 1, world.playerCount do s = s + world.players[i].score end
  return s
end

local function row(kind, wave, boss, seconds, deaths, causes, world, reason)
  write(string.format("%s,%s,%s,%d,%d,%d,%.1f,%d,%s,%s,%s,%d,%s\n",
    kind, S.id, S.date, world.playerCount, wave, boss and 1 or 0, seconds, deaths,
    causes, lives(world), upgrades(world), score(world), reason or ""))
end

local function isBoss(wave)
  return wave >= 1 and wave % Config.BOSS.every == 0
end

-- A new match (Game:enter).
function RunLog.begin(world)
  S.on = not Config.SMOKE or Config.SMOKE_LOG or false
  S.finished = false
  S.world = world
  S.id = os.date("%Y%m%d-%H%M%S")
  S.date = os.date("%Y-%m-%d %H:%M")
  S.total, S.wave, S.waveT, S.deaths, S.runDeaths = 0, 0, 0, 0, 0
  for k = #S.causes, 1, -1 do S.causes[k] = nil end
  S.lastCause = ""
end

-- Game time (Game:update only runs unpaused, with no overlay on top).
function RunLog.tick(dt)
  S.total = S.total + dt
  S.waveT = S.waveT + dt
end

function RunLog.waveStart(n)
  S.wave, S.waveT, S.deaths = n, 0, 0
  for k = #S.causes, 1, -1 do S.causes[k] = nil end
end

-- A player actually died (the bubble did not hold); `cause` = enemy type,
-- "boss", or the shot's source ("shooter", "boss", "sniper", "bossMissile").
function RunLog.death(p, cause)
  local c = "P" .. p.index .. ":" .. tostring(cause or "?")
  S.deaths, S.runDeaths = S.deaths + 1, S.runDeaths + 1
  S.causes[#S.causes + 1] = c
  S.lastCause = c
end

function RunLog.waveEnd(world)
  if not S.on or S.finished then return end
  row("wave", S.wave, isBoss(S.wave), S.waveT, S.deaths, table.concat(S.causes, "|"), world)
end

-- The match is over: `reason` "fim" (game over) or "abandono" (quit from
-- the pause menu). Writes the wave it ended in and the match summary, once.
function RunLog.finish(world, reason)
  if not S.on or S.finished then return end
  S.finished = true
  if S.wave < 1 or S.total <= 0 then return end   -- left from the briefing: no match
  do
    row("wave_fatal", S.wave, isBoss(S.wave), S.waveT, S.deaths, table.concat(S.causes, "|"), world)
  end
  row("partida", S.wave, false, S.total, S.runDeaths, S.lastCause, world, reason)
end

-- The game is closing (love.quit): a match still going is closed as "saiu".
function RunLog.quit()
  if S.world then RunLog.finish(S.world, "saiu") end
end

RunLog.FILE = FILE
return RunLog
