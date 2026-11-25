-- Art loader: Kenney sprite sheets (XML atlases), UIPack images and fonts.
--
-- Everything is created in Assets.load(), never during gameplay. Each sprite
-- role in Config.ART.sprites is cut out of its sheet into its own Image:
--   * with transparent padding, so mipmaps never bleed in a neighbor sprite
--     (Kenney sheets are packed with zero spacing);
--   * with "alpha bleed": fully transparent texels take the color of the
--     nearest opaque one. Kenney PNGs store transparency as black, which
--     would otherwise show up as a dark halo under linear filtering.
-- A missing file or sprite never crashes the game: it is logged and replaced
-- by a magenta placeholder, the same "degrade, don't die" rule as src/audio.lua.

local Config = require("src.config")

local Assets = {
  sprites = {},   -- role -> { image, w, h, rot, scale(size) }
  ui = {},        -- UIPack path -> Image
  fonts = {},     -- role -> Font
  loaded = 0,
  missing = 0,
}

local PAD = 2           -- transparent border around each extracted sprite
local BLEED_PASSES = 3  -- how far (px) edge colors are pushed into transparency

local placeholder

-- Parses a Kenney TextureAtlas XML into name -> {x, y, w, h}.
local function parseAtlas(path)
  local ok, text = pcall(love.filesystem.read, path)
  if not ok or not text then return nil end
  local rects = {}
  for name, x, y, w, h in text:gmatch(
      '<SubTexture name="([^"]+)" x="(%d+)" y="(%d+)" width="(%d+)" height="(%d+)"') do
    rects[name:gsub("%.png$", "")] = { tonumber(x), tonumber(y), tonumber(w), tonumber(h) }
  end
  return rects
end

-- Pushes opaque colors into neighboring fully transparent texels (RGB only,
-- alpha stays 0), a few pixels deep. Works in place on an ImageData.
local function alphaBleed(data)
  local w, h = data:getDimensions()
  local snapshot = data:clone()
  for _ = 1, BLEED_PASSES do
    local filled = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = snapshot:getPixel(x, y)
        if a == 0 then
          local sr, sg, sb, n = 0, 0, 0, 0
          for dy = -1, 1 do
            local ny = y + dy
            if ny >= 0 and ny < h then
              for dx = -1, 1 do
                local nx = x + dx
                if nx >= 0 and nx < w and (dx ~= 0 or dy ~= 0) then
                  local r, g, b, na = snapshot:getPixel(nx, ny)
                  if na > 0 then sr, sg, sb, n = sr + r, sg + g, sb + b, n + 1 end
                end
              end
            end
          end
          if n > 0 then
            -- Tiny alpha marks the texel as "already bled" for the next pass;
            -- it is reset to 0 at the end.
            data:setPixel(x, y, sr / n, sg / n, sb / n, 1 / 255)
            filled = filled + 1
          end
        end
      end
    end
    if filled == 0 then break end
    snapshot:paste(data, 0, 0, 0, 0, w, h)
  end
  data:mapPixel(function(_, _, r, g, b, a)
    if a <= 1 / 255 + 1e-6 then return r, g, b, 0 end
    return r, g, b, a
  end)
end

local function newSmoothImage(data, mipmaps)
  -- WebGL 1 (the browser build) can't mipmap non-power-of-two textures, and
  -- the cut sprites are any size: there they go without mipmaps.
  if mipmaps and not love.graphics.getSupported().fullnpot then mipmaps = false end
  local img = love.graphics.newImage(data, { mipmaps = mipmaps })
  img:setFilter("linear", "linear")
  if mipmaps then img:setMipmapFilter("linear") end
  return img
end

local function makePlaceholder()
  local d = love.image.newImageData(8, 8)
  d:mapPixel(function() return 1, 0, 1, 1 end)
  local img = love.graphics.newImage(d)
  img:setFilter("nearest", "nearest")
  return img
end

local function loadSheets()
  local sheets = {}
  for id, def in pairs(Config.ART.sheets) do
    local okImg, data = pcall(love.image.newImageData, def.image)
    local rects = parseAtlas(def.atlas)
    if okImg and rects then
      sheets[id] = { data = data, rects = rects }
    else
      print(string.format("[assets] sheet '%s' unavailable (%s / %s)", id, def.image, def.atlas))
    end
  end
  return sheets
end

-- Turns a sprite into greyscale, normalized so its brightest opaque texel is
-- white. Tinting a colored sprite multiplies colors (an orange flame tinted
-- blue comes out green); a white-based one takes the tint exactly.
local function toGrey(data)
  local maxLum = 0
  data:mapPixel(function(_, _, r, g, b, a)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if a > 0 and lum > maxLum then maxLum = lum end
    return lum, lum, lum, a
  end)
  if maxLum <= 0 then return end
  local k = 1 / maxLum
  data:mapPixel(function(_, _, r, _, _, a)
    local v = math.min(1, r * k)
    return v, v, v, a
  end)
end

local function extractSprite(sheet, rect, grey)
  local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
  local d = love.image.newImageData(w + PAD * 2, h + PAD * 2)
  d:paste(sheet.data, PAD, PAD, x, y, w, h)
  if grey then toGrey(d) end
  alphaBleed(d)
  return newSmoothImage(d, true), w, h
end

-- Outline silhouette: the sprite's alpha dilated by `r` texels, all white (so
-- setColor tints it exactly). Drawn under the sprite at the same size and
-- angle, only the rim shows. It needs a wider transparent border (PAD + r) so
-- the dilation has room; that pad is stored in the sprite record, and the
-- record keeps the ORIGINAL w/h so Assets.draw scales it like the sprite.
local function extractOutline(sheet, rect, r)
  local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
  local pad = PAD + r
  local dw, dh = w + pad * 2, h + pad * 2
  local d = love.image.newImageData(dw, dh)
  d:paste(sheet.data, pad, pad, x, y, w, h)
  local snapshot = d:clone()
  -- r passes of a 3x3 max filter on alpha.
  for _ = 1, r do
    for py = 0, dh - 1 do
      for px = 0, dw - 1 do
        local a = 0
        for oy = -1, 1 do
          local ny = py + oy
          if ny >= 0 and ny < dh then
            for ox = -1, 1 do
              local nx = px + ox
              if nx >= 0 and nx < dw then
                local _, _, _, na = snapshot:getPixel(nx, ny)
                if na > a then a = na end
              end
            end
          end
        end
        d:setPixel(px, py, 1, 1, 1, a)
      end
    end
    snapshot:paste(d, 0, 0, 0, 0, dw, dh)
  end
  return newSmoothImage(d, true), w, h, pad
end

local function loadSprites(sheets)
  for role, def in pairs(Config.ART.sprites) do
    local sheetId, name = def[1]:match("^(%w+):(.+)$")
    local sheet = sheets[sheetId]
    local rect = sheet and sheet.rects[name]
    if rect then
      local img, w, h, pad
      if def.outline then
        img, w, h, pad = extractOutline(sheet, rect, def.outline)
      else
        img, w, h = extractSprite(sheet, rect, def.grey)
      end
      Assets.sprites[role] = { image = img, w = w, h = h, rot = def.rot or 0, pad = pad or PAD }
      Assets.loaded = Assets.loaded + 1
    else
      print(string.format("[assets] sprite '%s' (%s) not found", role, def[1]))
      Assets.sprites[role] = { image = placeholder, w = 8, h = 8, rot = 0, pad = 0 }
      Assets.missing = Assets.missing + 1
    end
  end
end

-- Debris: each sprite gets 4 quads, its quadrants (top-left, top-right,
-- bottom-left, bottom-right in texture space), over its own image. Order
-- matches QUADRANT_SIGNS below.
Assets.QUADRANT_SIGNS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

local function makeQuadrants()
  for _, s in pairs(Assets.sprites) do
    local iw, ih = s.image:getDimensions()
    local hw, hh = s.w * 0.5, s.h * 0.5
    s.quads = {
      love.graphics.newQuad(s.pad, s.pad, hw, hh, iw, ih),
      love.graphics.newQuad(s.pad + hw, s.pad, hw, hh, iw, ih),
      love.graphics.newQuad(s.pad, s.pad + hh, hw, hh, iw, ih),
      love.graphics.newQuad(s.pad + hw, s.pad + hh, hw, hh, iw, ih),
    }
  end
end

-- Draws quadrant `q` (1..4) of a sprite role, centered on (x, y), at the
-- scale the whole sprite would have at `size` (as Assets.draw).
function Assets.drawQuadrant(role, q, x, y, angle, size)
  local s = Assets.sprites[role]
  if not s then return end
  local k = size / math.max(s.w, s.h)
  love.graphics.draw(s.image, s.quads[q], x, y, (angle or 0) - s.rot, k, k, s.w * 0.25, s.h * 0.25)
end

local function loadFonts()
  for role, def in pairs(Config.ART.fonts) do
    local ok, font = pcall(love.graphics.newFont, def.file, def.size, "mono")
    if not ok then
      print(string.format("[assets] font '%s' failed (%s): using default", role, def.file))
      font = love.graphics.newFont(def.size)
    end
    font:setFilter("nearest", "nearest")
    Assets.fonts[role] = font
  end
end

function Assets.load()
  local t0 = love.timer.getTime()
  placeholder = makePlaceholder()
  -- 1x1 white texel: stretched into spark streaks (one texture, so the
  -- draws batch) and the boss shield quad.
  local px = love.image.newImageData(1, 1)
  px:setPixel(0, 0, 1, 1, 1, 1)
  Assets.white = love.graphics.newImage(px)
  local sheets = loadSheets()
  loadSprites(sheets)
  makeQuadrants()
  loadFonts()
  -- The sheet ImageData (~5 MB for spaceShooter2) is only needed for cutting.
  for _, s in pairs(sheets) do s.data:release() end
  print(string.format("[assets] %d sprite(s) loaded, %d missing (%.0f ms)",
    Assets.loaded, Assets.missing, (love.timer.getTime() - t0) * 1000))
end

-- Sprite record for a role from Config.ART.sprites.
function Assets.sprite(role)
  return Assets.sprites[role]
end

function Assets.font(role)
  return Assets.fonts[role]
end

-- UIPack image by path relative to Config.ART.uiDir (e.g. "Extra/panel_glass").
-- Loaded lazily but cached; callers must request them at load time (src/ui.lua
-- does) so nothing is created mid-game. `mipmaps` for pieces drawn much
-- smaller than their texture (reticle, badges); 9-slice pieces skip them.
function Assets.uiImage(path, mipmaps)
  local img = Assets.ui[path]
  if img then return img end
  local ok, data = pcall(love.image.newImageData, Config.ART.uiDir .. path .. ".png")
  if ok then
    alphaBleed(data)
    img = newSmoothImage(data, mipmaps)
  else
    print(string.format("[assets] UI image '%s' not found", path))
    img = placeholder
  end
  Assets.ui[path] = img
  return img
end

-- Draws a sprite role centered at (x, y), scaled so its longest side is `size`
-- logical px, facing `angle` (radians, 0 = right). Color comes from the
-- current love.graphics color, so callers tint with setColor as usual.
function Assets.draw(role, x, y, angle, size, stretchX, stretchY)
  local s = Assets.sprites[role]
  if not s then return end
  local k = size / math.max(s.w, s.h)
  love.graphics.draw(s.image, x, y, (angle or 0) - s.rot,
    k * (stretchX or 1), k * (stretchY or 1), s.w * 0.5 + s.pad, s.h * 0.5 + s.pad)
end

return Assets
