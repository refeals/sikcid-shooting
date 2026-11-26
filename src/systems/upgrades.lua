-- Permanent upgrades: definitions (data), offer rules and application.
--
-- A player's upgrades live in `player.upgrades` (id -> level) and
-- `player.upgradeOrder` (ids in the order they were first taken, for the
-- HUD). Like the power-ups, their effect is never "undone": Player:resetMods
-- calls Upgrades.apply, which writes the base layer of player.mods, and the
-- temporary power-ups apply on top of it (see Powerups.recompute).
--
-- Two groups:
--   stats   -- stack up to `max` times (numbers in Config.UPGRADES)
--   uniques -- `unique = true`, 3 levels: base, "+" and "++". A level shows
--              up in an offer only once the previous one is owned.

local Config = require("src.config")
local Util   = require("src.util")
local S      = require("src.i18n").S

local U = Config.UPGRADES

local Upgrades = {}

-- Names and descriptions live in src/lang: S.upgrade_name[id] and
-- S.upgrade_desc[id], one line per level (stats have one). The letter on
-- the icon is the same in every language.
Upgrades.DEFS = {
  { id = "cadence", letter = "C", max = U.cadence.max },
  { id = "motor", letter = "M", max = U.motor.max },
  { id = "thruster", letter = "J", max = U.thruster.max },
  { id = "duration", letter = "T", max = U.duration.max },
  { id = "hull", letter = "A", max = U.hull.max },
  { id = "magnet", letter = "I", max = U.magnet.max },
  { id = "pierce", letter = "P", max = 3, unique = true },
  { id = "rear", letter = "R", max = 3, unique = true },
  { id = "loyal", letter = "D", max = 3, unique = true },
  { id = "blade", letter = "L", max = 3, unique = true },
  { id = "recharge", letter = "B", max = 3, unique = true },
  { id = "ricochet", letter = "Q", max = 3, unique = true },
  { id = "shock", letter = "Z", max = 3, unique = true },
}

-- Filler card when nothing else is left to offer.
Upgrades.LIFE_CARD = { id = "life", letter = "+", max = math.huge, instant = true }

local byId = {}
for i = 1, #Upgrades.DEFS do byId[Upgrades.DEFS[i].id] = Upgrades.DEFS[i] end
byId.life = Upgrades.LIFE_CARD

function Upgrades.byId(id) return byId[id] end

function Upgrades.level(p, id)
  return p.upgrades[id] or 0
end

function Upgrades.color(def)
  return def.unique and U.uniqueColor or U.statColor
end

-- Card/list label for `def` at `level`: uniques get "+"/"++", stats
-- "N/MAX" (one-level stats and the life card just their name).
local TIER_SUFFIX = { "", "+", "++" }

function Upgrades.label(def, level)
  local name = S.upgrade_name[def.id]
  if def.unique then return name .. (TIER_SUFFIX[level] or "") end
  if def.max > 1 and def.max < math.huge then
    return string.format("%s %d/%d", name, level, def.max)
  end
  return name
end

-- Card title (narrow cards): uniques with their "+"/"++", stats just the
-- name (their "N/MAX" goes in a corner, see Upgrades.count).
function Upgrades.cardTitle(def, level)
  local name = S.upgrade_name[def.id]
  if def.unique then return name .. (TIER_SUFFIX[level] or "") end
  return name
end

-- "N/MAX" for stacking stats, nil otherwise.
function Upgrades.count(def, level)
  if def.unique or def.max <= 1 or def.max == math.huge then return nil end
  return string.format("%d/%d", level, def.max)
end

function Upgrades.desc(def, level)
  local lines = S.upgrade_desc[def.id]
  return lines[math.min(level, #lines)]
end

-- ---------------------------------------------------------------------------
-- Offers. Candidates go in a reused buffer; `out` gets { def, level } slots
-- (reused tables, filled in place).
-- ---------------------------------------------------------------------------
local cand, candN = {}, 0

local function gather(p, pred)
  candN = 0
  for i = 1, #Upgrades.DEFS do
    local def = Upgrades.DEFS[i]
    local lvl = Upgrades.level(p, def.id)
    if lvl < def.max and pred(def, lvl) then
      candN = candN + 1
      cand[candN] = def
    end
  end
end

local function taken(out, n, def)
  for i = 1, n do
    if out[i].def == def then return true end
  end
  return false
end

-- Moves a random candidate into out[n] (removes it from the buffer).
local function draw(p, out, n)
  if candN == 0 then return false end
  local k = math.random(candN)
  local def = cand[k]
  cand[k] = cand[candN]
  candN = candN - 1
  out[n].def, out[n].level = def, Upgrades.level(p, def.id) + 1
  return true
end

local function isTier(p, def)
  return def.unique and Upgrades.level(p, def.id) >= 1
end

local function slot(out, n)
  out[n] = out[n] or { def = nil, level = 1 }
  return out[n]
end

-- Fills out[1..count] with cards for player `p`. `boss`: the reward after a
-- boss (uniques only, at least one tier-up when one is possible); otherwise
-- any group, at most one tier-up card. Nothing left -> the life card.
function Upgrades.offer(p, boss, out, count)
  count = count or 3
  for i = 1, count do slot(out, i).def = nil end
  local n = 0

  if boss then
    -- One tier-up first, if any unique can level up.
    gather(p, function(def, lvl) return def.unique and lvl >= 1 end)
    if draw(p, out, n + 1) then n = n + 1 end
    -- Then any other unique (new or tier-up), then stats.
    gather(p, function(def) return def.unique and not taken(out, n, def) end)
    while n < count and draw(p, out, n + 1) do n = n + 1 end
    if n < count then
      gather(p, function(def) return not def.unique end)
      while n < count and draw(p, out, n + 1) do n = n + 1 end
    end
  else
    gather(p, function() return true end)
    local tiers = 0
    while n < count and candN > 0 do
      local k = math.random(candN)
      local def = cand[k]
      cand[k] = cand[candN]
      candN = candN - 1
      local tier = isTier(p, def)
      if not tier or tiers == 0 then
        if tier then tiers = tiers + 1 end
        n = n + 1
        out[n].def, out[n].level = def, Upgrades.level(p, def.id) + 1
      end
    end
  end

  -- Filler: the life card (only once per offer).
  if n < count then
    n = n + 1
    out[n].def, out[n].level = Upgrades.LIFE_CARD, 1
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Taking and applying.
-- ---------------------------------------------------------------------------
function Upgrades.take(p, def)
  if def.instant then
    -- Life card: +1 life now, up to the max.
    if p.lives < p.maxLives then p.lives = p.lives + 1 end
    return
  end
  local lvl = Upgrades.level(p, def.id) + 1
  if lvl == 1 then p.upgradeOrder[#p.upgradeOrder + 1] = def.id end
  p.upgrades[def.id] = lvl
  if def.id == "hull" then
    p.maxLives = p.maxLives + 1
    -- A player who ran out is coming back anyway (+1 life at the wave end);
    -- the extra life counts for them too.
    p.lives = p.lives + 1
  end
  require("src.systems.powerups").recompute(p)
end

-- Base layer of player.mods (Player:resetMods): written before the
-- temporary power-ups apply theirs.
function Upgrades.apply(p, m)
  local L = p.upgrades
  local n
  n = L.cadence or 0
  if n > 0 then m.fireRateMul = m.fireRateMul * U.cadence.mul ^ n end
  n = L.motor or 0
  if n > 0 then m.speedMul = m.speedMul * U.motor.mul ^ n end
  n = L.thruster or 0
  if n > 0 then m.dashCdMul = m.dashCdMul * U.thruster.mul ^ n end
  n = L.duration or 0
  if n > 0 then m.durationMul = m.durationMul * U.duration.mul ^ n end
  if (L.magnet or 0) > 0 then m.magnet = U.magnet.radius end
  n = L.pierce or 0
  if n > 0 then m.pierce = U.pierce[n] end
  n = L.rear or 0
  if n > 0 then m.rearRate, m.rearFan = U.rear.rates[n], U.rear.fan[n] end
  n = L.loyal or 0
  if n > 0 then m.loyalCount, m.loyalRate = U.loyal.counts[n], U.loyal.rates[n] end
  n = L.blade or 0
  if n > 0 then m.blade, m.bladeReset = U.blade.damage[n], U.blade.resetOnKill[n] end
  n = L.recharge or 0
  if n > 0 then m.recharge, m.popNova = U.recharge.interval[n], U.recharge.popNova[n] end
  n = L.ricochet or 0
  if n > 0 then m.bounces, m.bounceHoming = U.ricochet.bounces[n], U.ricochet.homing[n] end
  n = L.shock or 0
  if n > 0 then
    m.shockRadius, m.shockDamage, m.shockStart = U.shock.radius[n], U.shock.damage[n], U.shock.onStart[n]
  end
end

-- ---------------------------------------------------------------------------
-- Icon: a square badge (the temporary power-ups are round) in the group
-- color with the letter, and one more light outline per level above 1.
-- Centered at (x, y), `s` px wide. Shared by the cards, the HUD and pause.
-- ---------------------------------------------------------------------------
local INK = { 0.08, 0.08, 0.12, 1 }

function Upgrades.drawIcon(def, level, x, y, s, alpha)
  local UI = require("src.ui")
  local Assets = require("src.assets")
  local g = love.graphics
  alpha = alpha or 1
  UI.squareBadge(Upgrades.color(def), x, y, s, alpha)
  local font = Assets.font(s >= 20 and "title" or "titleSmall")
  g.setFont(font)
  g.setColor(INK[1], INK[2], INK[3], alpha)
  g.print(def.letter, math.floor(x - font:getWidth(def.letter) * 0.5 + 0.5),
    math.floor(y - font:getHeight() * 0.5 + 1))
  g.setFont(Assets.font("body"))
  for k = 2, level do
    local o = s * 0.5 + (k - 1) * 2
    g.setColor(1, 1, 1, alpha * (0.35 + 0.3 * (k - 1)))
    g.rectangle("line", math.floor(x - o) + 0.5, math.floor(y - o) + 0.5, o * 2, o * 2)
  end
  g.setColor(1, 1, 1, 1)
end

-- Takes a random card of a fresh offer (--upgrades N, debug).
local randomOut = {}
function Upgrades.randomTake(p, boss)
  local n = Upgrades.offer(p, boss, randomOut, 3)
  Upgrades.take(p, randomOut[Util.randInt(1, n)].def)
end

return Upgrades
