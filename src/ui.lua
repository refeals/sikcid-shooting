-- UI drawing helpers built on Kenney's UIPack.
--
-- All pieces come from the Grey/Extra sets and are tinted with setColor: the
-- grey base tone (218/255) times the tint gives the requested color, so any
-- RGB works (player colors included) without needing a pre-colored PNG.
-- Sizes are in logical px; UIPack texels are drawn at Config.ART.uiScale.
--
-- Every image and Quad is created in UI.load(); drawing allocates nothing.

local Config = require("src.config")
local Assets = require("src.assets")

local UI = {}

local S = Config.ART.uiScale
local GREY_BASE = 218 / 255   -- base tone of the Grey/Extra pieces

local img = {}
local panelQuads = {}         -- 9-slice quads per panel style
local PANEL_BORDER = 8        -- texels kept unstretched at each panel edge

local PANELS = {
  glass = "Extra/panel_glass",
  screws = "Extra/panel_glass_screws",
}

-- Sets a tint so the grey base tone ends up as `c` (clamped), times `alpha`.
local function tint(c, alpha)
  local k = 1 / GREY_BASE
  love.graphics.setColor(math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k),
    (c[4] or 1) * (alpha or 1))
end

local function makeNineSlice(image, b)
  local w, h = image:getDimensions()
  local xs = { 0, b, w - b }
  local ws = { b, w - 2 * b, b }
  local ys = { 0, b, h - b }
  local hs = { b, h - 2 * b, b }
  local q = {}
  for row = 1, 3 do
    for col = 1, 3 do
      q[#q + 1] = love.graphics.newQuad(xs[col], ys[row], ws[col], hs[row], w, h)
    end
  end
  return { image = image, quads = q, b = b, midW = w - 2 * b, midH = h - 2 * b }
end

function UI.load()
  for style, path in pairs(PANELS) do
    panelQuads[style] = makeNineSlice(Assets.uiImage(path), PANEL_BORDER)
  end
  img.tabL = Assets.uiImage("Grey/bar_square_large_l")
  img.tabM = Assets.uiImage("Grey/bar_square_large_m")
  img.tabR = Assets.uiImage("Grey/bar_square_large_r")
  img.barL = Assets.uiImage("Grey/bar_round_small_l")
  img.barM = Assets.uiImage("Grey/bar_round_small_m")
  img.barR = Assets.uiImage("Grey/bar_round_small_r")
  img.trackL = Assets.uiImage("Extra/bar_shadow_round_small_l")
  img.trackM = Assets.uiImage("Extra/bar_shadow_round_small_m")
  img.trackR = Assets.uiImage("Extra/bar_shadow_round_small_r")
  img.badge = Assets.uiImage("Grey/bar_round_large_square", true)
  img.crosshair = Assets.uiImage("Extra/crosshair_b", true)
end

-- 9-slice panel. `color` tints the whole panel ({r,g,b,a}); defaults to the
-- dark glass of Config.ART.ui.
function UI.panel(x, y, w, h, color, style)
  local p = panelQuads[style or "glass"]
  if not p then return end
  tint(color or Config.ART.ui.panel)
  local b = p.b * S
  local midW, midH = math.max(0, w - 2 * b), math.max(0, h - 2 * b)
  local sx = midW / p.midW
  local sy = midH / p.midH
  local q = p.quads
  local x1, x2 = x + b, x + b + midW
  local y1, y2 = y + b, y + b + midH
  local g = love.graphics
  g.draw(p.image, q[1], x, y, 0, S, S)
  g.draw(p.image, q[2], x1, y, 0, sx, S)
  g.draw(p.image, q[3], x2, y, 0, S, S)
  g.draw(p.image, q[4], x, y1, 0, S, sy)
  g.draw(p.image, q[5], x1, y1, 0, sx, sy)
  g.draw(p.image, q[6], x2, y1, 0, S, sy)
  g.draw(p.image, q[7], x, y2, 0, S, S)
  g.draw(p.image, q[8], x1, y2, 0, sx, S)
  g.draw(p.image, q[9], x2, y2, 0, S, S)
end

-- Draws a horizontal 3-piece strip (left cap, stretched middle, right cap)
-- `h` logical px tall.
local function strip(l, m, r, x, y, w, h)
  local lw, lh = l:getDimensions()
  local rw = r:getWidth()
  local mw = m:getWidth()
  local k = h / lh                        -- uniform scale from height
  local capL, capR = lw * k, rw * k
  local mid = math.max(0, w - capL - capR)
  love.graphics.draw(l, x, y, 0, k, k)
  if mid > 0 then love.graphics.draw(m, x + capL, y, 0, mid / mw, k) end
  love.graphics.draw(r, x + capL + mid, y, 0, k, k)
end

-- Colored header tab with centered text (font role from Config.ART.fonts).
function UI.tab(color, text, x, y, w, h, fontRole, textColor)
  h = h or 12
  tint(color)
  strip(img.tabL, img.tabM, img.tabR, x, y, w, h)
  if text then
    local font = Assets.font(fontRole or "body")
    love.graphics.setFont(font)
    love.graphics.setColor(textColor or Config.COLORS.text)
    love.graphics.printf(text, math.floor(x), math.floor(y + (h - font:getHeight()) * 0.5 + 1),
      math.floor(w), "center")
    love.graphics.setFont(Assets.font("body"))
  end
end

-- Progress bar: dark rounded track plus a fill of `frac` (0..1) in `color`.
function UI.bar(color, x, y, w, frac, h)
  h = h or 6
  love.graphics.setColor(1, 1, 1, 1)
  strip(img.trackL, img.trackM, img.trackR, x, y, w, h)
  frac = math.max(0, math.min(1, frac or 0))
  if frac > 0 then
    -- The fill never shrinks below its two caps, so it fades instead.
    local caps = (img.barL:getWidth() + img.barR:getWidth()) * (h / img.barL:getHeight())
    local fw = w * frac
    local alpha = 1
    if fw < caps then alpha = fw / caps; fw = caps end
    tint(color, alpha)
    strip(img.barL, img.barM, img.barR, x, y, fw, h)
  end
end

-- Round badge (pickups / power-up icons) centered at (x, y), `size` px wide.
function UI.badge(color, x, y, size, alpha)
  local w = img.badge:getWidth()
  local k = size / w
  tint(color, alpha)
  love.graphics.draw(img.badge, x, y, 0, k, k, w * 0.5, w * 0.5)
end

-- Aiming reticle centered at (x, y).
function UI.crosshair(color, x, y, size, alpha)
  local w = img.crosshair:getWidth()
  local k = size / w
  love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
  love.graphics.draw(img.crosshair, x, y, 0, k, k, w * 0.5, w * 0.5)
end

-- Text in a font role. align: "left" | "center" | "right" within `w`
-- (defaults to plain print when no width is given).
function UI.text(fontRole, str, x, y, color, w, align)
  love.graphics.setFont(Assets.font(fontRole))
  love.graphics.setColor(color or Config.COLORS.text)
  if w then
    love.graphics.printf(str, math.floor(x), math.floor(y), math.floor(w), align or "left")
  else
    love.graphics.print(str, math.floor(x), math.floor(y))
  end
  -- Body is the default font everywhere; leave it set for plain prints.
  love.graphics.setFont(Assets.font("body"))
end

return UI
