-- Game text in three languages: src/lang/en.lua, es.lua and pt.lua.
--
-- I18n.S is the one table every screen reads its text from:
--
--   local S = require("src.i18n").S
--   UI.text("title", S.menu_play, ...)
--
-- I18n.set fills it IN PLACE (English first, then the chosen language over
-- it, so a key a language lacks shows the English text), so the reference
-- each module holds never goes stale. The rule that keeps a language switch
-- instant: read S.x where it is used, never copy it into a local at module
-- load (the copy would keep the old language). Text built once from S (the
-- wrapped COMO JOGAR rules, joined lines) is rebuilt when I18n.version
-- changes. A lookup allocates nothing, so S is fine in the hot loop.
--
-- Values are strings (some are string.format patterns) or tables of data
-- (names by id, the lines of a list). A key no file defines reads as
-- "#key": a typo shows on screen instead of crashing a print.
--
-- The language only changes on the OPÇÕES screen, which opens from the main
-- menu: never in the middle of a match.

local I18n = {
  CODES = { "en", "es", "pt" },
  -- Shown as is in every language, so a player who switched by mistake can
  -- still find their own.
  NATIVE = { "ENGLISH", "ESPAÑOL", "PORTUGUÊS" },
  DEFAULT = "en",
  code = nil,       -- the language in S
  version = 0,      -- bumped by every I18n.set that changes the language
  S = {},
}

local S = I18n.S
setmetatable(S, { __index = function(_, k) return "#" .. tostring(k) end })

local files = {}
local function file(code)
  if not files[code] then files[code] = require("src.lang." .. code) end
  return files[code]
end

function I18n.valid(code)
  for i = 1, #I18n.CODES do
    if I18n.CODES[i] == code then return true end
  end
  return false
end

-- Switches the language (an unknown code falls back to the default).
function I18n.set(code)
  if not I18n.valid(code) then code = I18n.DEFAULT end
  if code == I18n.code then return end
  for k in pairs(S) do S[k] = nil end
  for k, v in pairs(file(I18n.DEFAULT)) do S[k] = v end
  if code ~= I18n.DEFAULT then
    for k, v in pairs(file(code)) do S[k] = v end
  end
  I18n.code = code
  I18n.version = I18n.version + 1
end

-- A number for running text: whole numbers without decimals, others with
-- one, in the language's decimal separator ("2.5" / "2,5").
function I18n.num(v)
  if v == math.floor(v) then return string.format("%d", v) end
  local s = string.format("%.1f", v)
  if S.decimal ~= "." then s = (s:gsub("%.", S.decimal)) end
  return s
end

-- ---------------------------------------------------------------------------
-- Parity check (smoke test): every language has the keys of the default one,
-- with the same types, the same table shapes and the same string.format
-- specifiers in the same order, and no key the default lacks.
-- ---------------------------------------------------------------------------
-- The format specifiers of a string, in order ("%d %s %.1f"). Only real
-- conversions count: the "%" in "+20% DE CADÊNCIA" is plain text.
local function specs(s)
  local out = {}
  for spec in s:gmatch("%%[-+0#]*%d*%.?%d*[dsfxiq%%]") do out[#out + 1] = spec end
  return table.concat(out, " ")
end

local function compare(ref, other, path, code, errors)
  for k, v in pairs(ref) do
    local p = path .. "." .. tostring(k)
    local o = other[k]
    if o == nil then
      errors[#errors + 1] = string.format("%s: missing %s", code, p)
    elseif type(o) ~= type(v) then
      errors[#errors + 1] = string.format("%s: %s is a %s, not a %s", code, p, type(o), type(v))
    elseif type(v) == "table" then
      compare(v, o, p, code, errors)
    elseif type(v) == "string" and specs(v) ~= specs(o) then
      errors[#errors + 1] = string.format("%s: %s has format \"%s\", not \"%s\"", code, p, specs(o), specs(v))
    end
  end
  for k in pairs(other) do
    if ref[k] == nil then
      errors[#errors + 1] = string.format("%s: extra %s.%s", code, path, tostring(k))
    end
  end
end

-- Returns a list of problems (empty when the files agree).
function I18n.check()
  local errors = {}
  local ref = file(I18n.DEFAULT)
  for i = 1, #I18n.CODES do
    local code = I18n.CODES[i]
    if code ~= I18n.DEFAULT then compare(ref, file(code), "S", code, errors) end
  end
  table.sort(errors)
  return errors
end

I18n.set(I18n.DEFAULT)

return I18n
