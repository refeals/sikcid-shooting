-- Store/frontend art generator: `love . --media`.
--
-- Renders, with the game's own sprites, sky, shaders and fonts:
--   media/cover.png   1260x1000  key art + logo (itch.io cover, Batocera
--                                image/thumbnail)
--   media/logo.png    1200x480   logo on transparency (Batocera marquee,
--                                itch.io page banner)
--   media/fanart.png  1920x1080  key art without the logo (Batocera fanart,
--                                itch.io page background)
--
-- Lives in tools/, so it never goes into the .love (build.sh packs only
-- main.lua, conf.lua, src/ and assets/). Output goes straight into media/ next
-- to main.lua (plain io, outside love.filesystem); if that fails it falls
-- back to the LÖVE save directory and says so.
--
-- The scene is static and deterministic: the clock is frozen (the sky is a
-- pure function of it) and every scattered detail comes from a seeded RNG.

local Config = require("src.config")

local Media = {}

-- Fake clock: the sky, the outline pulse and the engine flicker all read
-- love.timer.getTime. Frozen before anything loads so Background's t0 is 0.
local now = 0
love.timer.getTime = function() return now end

-- Sky time used for every image (picks where the drifting stars, the distant
-- objects and the shooting star are). Tuned by eye.
local SKY_TIME = 23.35

-- Sharper player ship for big renders: the same Kenney ship from the 2x sheet
-- (1x spaceShips_002 = 2x spaceShips_009), outline doubled to match.
Config.ART.sprites.playerShip = { "ss2x:spaceShips_009", rot = math.pi / 2 }
Config.ART.sprites.playerOutline = { "ss2x:spaceShips_009", rot = math.pi / 2, outline = 8 }

local Assets, Shaders, Background, UI, Player, Boss, Enemy

local VW, VH = Config.VIRTUAL_W, Config.VIRTUAL_H
local FONT_TITLE = "assets/art/Fonts/Kenney Rocket Square.ttf"
local FONT_BODY = "assets/art/Fonts/Kenney Mini Square.ttf"

local fontCache = {}
local function font(file, size)
  local key = file .. size
  if not fontCache[key] then
    local f = love.graphics.newFont(file, size, "mono")
    f:setFilter("nearest", "nearest")
    fontCache[key] = f
  end
  return fontCache[key]
end

-- Largest multiple of 8 (the fonts' pixel grid) at which every line fits `maxW`.
local function fitSize(file, lines, maxW, cap)
  local size = cap
  while size > 8 do
    local f, ok = font(file, size), true
    for _, l in ipairs(lines) do
      if f:getWidth(l) > maxW then ok = false break end
    end
    if ok then return size end
    size = size - 8
  end
  return 8
end

-- ---------------------------------------------------------------------------
-- Logo
-- ---------------------------------------------------------------------------
local LOGO_LINES = { "SIKCID", "SHOOTIN'" }
local LOGO_FILL = { { 0.92, 0.94, 1.00 }, { 1.00, 0.84, 0.30 } }   -- text white, DOURADO
local LOGO_EDGE = { 0.06, 0.05, 0.16 }
local LOGO_GLOW = { 0.30, 0.62, 1.00 }                           -- AZUL, the P1 color
local SUBTITLE = "TWIN-STICK SHOOTER DE ARENA - 1 OU 2 JOGADORES"

-- Text with a pixel-stepped outline: `r` px thick, drawn as offset copies.
local function outlined(f, str, x, y, fill, edge, r)
  local g = love.graphics
  g.setFont(f)
  local step = math.max(1, math.floor(r / 3))
  g.setColor(edge[1], edge[2], edge[3], edge[4] or 1)
  for dy = -r, r, step do
    for dx = -r, r, step do
      if dx * dx + dy * dy <= r * r * 1.1 then g.print(str, x + dx, y + dy) end
    end
  end
  g.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
  g.print(str, x, y)
end

-- Separable 9-tap Gaussian (linear-sampled), for the logo glow.
local BLUR_SRC = [[
uniform vec2 dir;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec4 s = Texel(tex, uv) * 0.2270270270;
    s += Texel(tex, uv + dir * 1.3846153846) * 0.3162162162;
    s += Texel(tex, uv - dir * 1.3846153846) * 0.3162162162;
    s += Texel(tex, uv + dir * 3.2307692308) * 0.0702702703;
    s += Texel(tex, uv - dir * 3.2307692308) * 0.0702702703;
    return s * color;
}
]]
local blurShader

-- Blurs `src` at 1/`down` resolution; returns the small blurred canvas
-- (draw it scaled by `down`). Leaves the canvas target as it found it.
local function blur(src, down, passes)
  local g = love.graphics
  blurShader = blurShader or g.newShader(BLUR_SRC)
  local target = g.getCanvas()
  local w, h = src:getDimensions()
  local sw, sh = math.ceil(w / down), math.ceil(h / down)
  local a, b = g.newCanvas(sw, sh), g.newCanvas(sw, sh)
  src:setFilter("linear", "linear")
  a:setFilter("linear", "linear")
  b:setFilter("linear", "linear")
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("alpha", "premultiplied")
  g.setCanvas(a)
  g.clear(0, 0, 0, 0)
  g.draw(src, 0, 0, 0, 1 / down, 1 / down)
  g.setShader(blurShader)
  for _ = 1, passes do
    blurShader:send("dir", { 1 / sw, 0 })
    g.setCanvas(b)
    g.clear(0, 0, 0, 0)
    g.draw(a)
    blurShader:send("dir", { 0, 1 / sh })
    g.setCanvas(a)
    g.clear(0, 0, 0, 0)
    g.draw(b)
  end
  g.setShader()
  g.setBlendMode("alpha")
  g.setCanvas(target)
  return a
end

-- Sizes of the logo for a max width: title font, line height, outline, and
-- (with the subtitle) its font and gap. `h` = total height.
local function logoLayout(maxW, withSubtitle)
  local L = { size = fitSize(FONT_TITLE, LOGO_LINES, maxW, 256) }
  L.font = font(FONT_TITLE, L.size)
  L.lineH = math.floor(L.size * 1.08)
  L.edge = math.max(4, math.floor(L.size / 14))
  L.h = L.lineH * #LOGO_LINES
  if withSubtitle then
    L.sub = font(FONT_BODY, fitSize(FONT_BODY, { SUBTITLE }, maxW * 0.95, math.max(16, L.size / 4)))
    L.gap = math.floor(L.size * 0.12)
    L.h = L.h + L.gap + L.sub:getHeight()
  end
  return L
end

-- Title lines (and subtitle) at cx/y. `fill` = nil draws the real colors;
-- a color draws a plain silhouette in it (the glow source).
local function logoText(L, cx, y, fill)
  local g = love.graphics
  for li, str in ipairs(LOGO_LINES) do
    local x = math.floor(cx - L.font:getWidth(str) * 0.5)
    local ly = y + (li - 1) * L.lineH
    if fill then
      outlined(L.font, str, x, ly, fill, fill, L.edge * 2)
    else
      -- Drop shadow, then the dark edge and the fill.
      g.setFont(L.font)
      g.setColor(0, 0, 0, 0.55)
      g.print(str, x + L.edge * 0.5, ly + L.edge * 1.6)
      outlined(L.font, str, x, ly, LOGO_FILL[li], LOGO_EDGE, L.edge)
    end
  end
  if L.sub then
    local sy = y + L.lineH * #LOGO_LINES + L.gap
    local sx = math.floor(cx - L.sub:getWidth(SUBTITLE) * 0.5)
    local r = math.max(2, math.floor(L.sub:getHeight() / 8))
    outlined(L.sub, SUBTITLE, sx, sy, fill or Config.COLORS.text, fill or LOGO_EDGE, fill and r * 3 or r)
  end
end

-- Logo centered at cx with its top at y, onto the current canvas: a blurred
-- P1-blue glow, then the letters.
local function drawLogo(L, cx, y)
  local g = love.graphics
  local target = g.getCanvas()
  local w, h = target:getDimensions()

  local sil = g.newCanvas(w, h)
  g.setCanvas(sil)
  g.clear(0, 0, 0, 0)
  logoText(L, cx, y, { 1, 1, 1, 1 })
  g.setCanvas(target)
  local soft = blur(sil, 4, 4)

  g.setBlendMode("add")
  g.setColor(LOGO_GLOW[1], LOGO_GLOW[2], LOGO_GLOW[3], 0.9)
  g.draw(soft, 0, 0, 0, 4, 4)
  g.setBlendMode("alpha")

  logoText(L, cx, y)
  g.setColor(1, 1, 1, 1)
end


-- ---------------------------------------------------------------------------
-- Key art scene
-- ---------------------------------------------------------------------------

-- Sky: the 640x360 background scaled to cover W x H. `fx`/`fy` (0..1) pick
-- which part of it shows when the aspect differs.
local function drawSky(W, H, theme, fx, fy)
  local g = love.graphics
  Background.reset(theme)
  -- One grid ripple, caught mid-way across the screen.
  now = SKY_TIME - 0.45
  Background.pulse(VW * 0.5, VH * 0.48, 0.6)
  now = SKY_TIME

  local z = math.max(W / VW, H / VH)
  local ox = (VW * z - W) * (fx or 0.5)
  local oy = (VH * z - H) * (fy or 0.5)
  g.push()
  g.translate(-ox, -oy)
  g.scale(z, z)
  Background.draw()
  Background.drawGrid({ x = 0, y = 0, w = VW, h = VH })
  g.pop()
end

-- Explosion in the game's style: smoke puffs in `color`, a hot additive core
-- and square sparks. `s` = size in scene px.
local function boom(rng, x, y, color, s)
  local g = love.graphics
  local puffs = { "puff1", "puff2", "puff3", "puff4" }
  for i = 1, 7 do
    local a, d = rng:random() * math.pi * 2, rng:random() * s * 0.35
    g.setColor(color[1], color[2], color[3], 0.55 + rng:random() * 0.3)
    Assets.draw(puffs[i % 4 + 1], x + math.cos(a) * d, y + math.sin(a) * d,
      rng:random() * math.pi * 2, s * (0.45 + rng:random() * 0.4))
  end
  g.setBlendMode("add")
  g.setColor(1, 0.85, 0.55, 0.85)
  Assets.draw("puff3", x, y, rng:random() * 6, s * 0.45)
  g.setColor(1, 1, 1, 0.7)
  Assets.draw("puff1", x, y, rng:random() * 6, s * 0.22)
  for _ = 1, 12 do
    local a, d = rng:random() * math.pi * 2, s * (0.35 + rng:random() * 0.6)
    local q = s * (0.03 + rng:random() * 0.04)
    g.setColor(color[1], color[2], color[3], 0.5 + rng:random() * 0.5)
    g.rectangle("fill", x + math.cos(a) * d - q * 0.5, y + math.sin(a) * d - q * 0.5, q, q)
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
end

-- A player shot (Kenney missile recolored) with its additive glow.
local function shot(color, x, y, angle, size)
  local g = love.graphics
  g.setBlendMode("add")
  g.setColor(color[1], color[2], color[3], 0.45)
  g.circle("fill", x, y, size * 0.45)
  g.setBlendMode("alpha")
  Shaders.recolor(color)
  g.setColor(1, 1, 1, 1)
  Assets.draw("shot", x, y, angle, size)
  Shaders.reset()
end

local function newEnemy(kind, x, y, angle)
  return setmetatable({
    type = kind, x = x, y = y, angle = angle, flash = 0,
    color = Config.COLORS[kind], def = Config.ENEMIES[kind], hp = Config.ENEMIES[kind].hp,
  }, Enemy)
end

local function angleTo(ax, ay, bx, by)
  return math.atan2(by - ay, bx - ax)
end

-- The whole scene in W x H px. Entities are placed in fractions of the image
-- and drawn in game units zoomed by `z`, so their real draw code (outline,
-- flames, reticle, boss engines) is reused as is.
local function drawScene(W, H, opts)
  local g = love.graphics
  drawSky(W, H, opts.theme, opts.skyX, opts.skyY)

  -- `top` (0..1) reserves the top of the image (the cover's logo): v maps
  -- into the part below it.
  local top = opts.top or 0
  local z = H / 250                     -- game px -> image px
  local function P(u, v) return u * W / z, (top + v * (1 - top)) * H / z end
  local rng = love.math.newRandomGenerator(opts.seed or 7)

  g.push()
  g.scale(z, z)

  -- Boss, facing down at the players.
  local boss = Boss.new()
  boss.active, boss.state = true, "fight"
  boss.hp, boss.maxHp = 1, 1
  boss.variant = Config.BOSS.variants[opts.bossVariant or 1]
  boss.size = opts.bossSize or 72
  boss.x, boss.y = P(opts.boss[1], opts.boss[2])
  boss.angle = math.pi / 2
  boss.thrust = 1.15

  local p1x, p1y = P(opts.p1[1], opts.p1[2])
  local p2x, p2y = P(opts.p2[1], opts.p2[2])

  -- Enemy shots (pink stars) fanning out from the boss and the shooters.
  local pink = Config.COLORS.bulletEnemy
  local function enemyShots(sx, sy, tx, ty, n, spread, from, step)
    local base = angleTo(sx, sy, tx, ty)
    for i = 1, n do
      local a = base + (i - (n + 1) / 2) * spread
      local d = from + (i % 2) * step * 0.5
      g.setColor(pink)
      Assets.draw("enemyShot", sx + math.cos(a) * d, sy + math.sin(a) * d, rng:random() * 6,
        Config.ART.size.enemyShot)
    end
  end
  enemyShots(boss.x, boss.y, (p1x + p2x) / 2, (p1y + p2y) / 2, 5, 0.32, boss.size * 0.75, 14)

  boss:draw()

  -- Enemies, each turned toward the closer player.
  local enemies = {}
  for _, e in ipairs(opts.enemies) do
    local x, y = P(e[2], e[3])
    local d1 = (x - p1x) ^ 2 + (y - p1y) ^ 2
    local d2 = (x - p2x) ^ 2 + (y - p2y) ^ 2
    local tx, ty = p1x, p1y
    if d2 < d1 then tx, ty = p2x, p2y end
    local en = newEnemy(e[1], x, y, e[1] == "tank" and rng:random() * 6 or angleTo(x, y, tx, ty))
    enemies[#enemies + 1] = en
    if e[1] == "shooter" then enemyShots(x, y, tx, ty, 2, 0.25, 16, 18) end
  end
  for _, en in ipairs(enemies) do en:draw() end

  -- Player shots: streams from each ship toward its target.
  local function stream(color, sx, sy, tx, ty, n, gap, first)
    local a = angleTo(sx, sy, tx, ty)
    local c, s = math.cos(a), math.sin(a)
    for i = 0, n - 1 do
      local d = first + i * gap
      local wob = (rng:random() - 0.5) * 3
      shot(color, sx + c * d - s * wob, sy + s * d + c * wob, a, Config.ART.size.shot)
    end
  end
  local c1, c2 = Config.PLAYER_PALETTE[opts.colors[1]].color, Config.PLAYER_PALETTE[opts.colors[2]].color
  for _, s in ipairs(opts.streams) do
    local from = s[1] == 1 and { p1x, p1y } or { p2x, p2y }
    local tx, ty = P(s[2], s[3])
    stream(s[1] == 1 and c1 or c2, from[1], from[2], tx, ty, s[4], 15, 22)
  end

  -- Explosions: on the boss hull and on enemies being shot down.
  for _, b in ipairs(opts.booms) do
    local x, y = P(b[1], b[2])
    boom(rng, x, y, b[4] or Config.COLORS.grunt, b[3])
  end

  -- Players, moving toward their aim so the engine flames show.
  local function ship(index, color, x, y, tx, ty)
    local p = Player.new(index, nil)
    p.color = color
    p.x, p.y = x, y
    p.angle = angleTo(x, y, tx, ty)
    p.aimX, p.aimY = math.cos(p.angle), math.sin(p.angle)
    p.vx, p.vy = p.aimX * Config.PLAYER.speed, p.aimY * Config.PLAYER.speed
    p.muzzle = 1
    p:draw()
  end
  ship(1, c1, p1x, p1y, P(opts.p1[3], opts.p1[4]))
  ship(2, c2, p2x, p2y, P(opts.p2[3], opts.p2[4]))

  g.pop()
  g.setColor(1, 1, 1, 1)
end

-- Same layout for every key art; only the frame and the logo change.
local SCENE = {
  theme = 1, bossVariant = 1, colors = { 1, 8 },   -- AZUL and DOURADO
  boss = { 0.50, 0.50 }, bossSize = 74,
  -- { u, v, aimU, aimV }
  p1 = { 0.30, 0.86, 0.46, 0.52 },
  p2 = { 0.71, 0.84, 0.56, 0.50 },
  enemies = {
    { "grunt",   0.14, 0.62 }, { "grunt",   0.22, 0.47 }, { "runner",  0.11, 0.80 },
    { "shooter", 0.84, 0.60 }, { "grunt",   0.90, 0.73 }, { "runner",  0.79, 0.43 },
    { "tank",    0.88, 0.95 }, { "grunt",   0.40, 0.72 }, { "runner",  0.62, 0.70 },
    { "shooter", 0.17, 0.95 },
  },
  -- { player, targetU, targetV, shots }
  streams = { { 1, 0.46, 0.55, 6 }, { 2, 0.55, 0.53, 6 }, { 1, 0.22, 0.47, 3 } },
  -- { u, v, size, color }
  booms = {
    { 0.45, 0.56, 34, { 1.00, 0.55, 0.20 } },
    { 0.57, 0.47, 22, { 1.00, 0.55, 0.20 } },
    { 0.26, 0.53, 26, Config.COLORS.grunt },
  },
}

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

-- Canvas pixels are premultiplied; PNGs are not. Only matters where alpha < 1
-- (the transparent logo).
local function unpremultiply(data)
  data:mapPixel(function(_, _, r, g, b, a)
    if a > 0 and a < 1 then return r / a, g / a, b / a, a end
    return r, g, b, a
  end)
end

local outDir, savedToSaveDir

local function save(name, canvas, transparent)
  local data = canvas:newImageData()
  if transparent then unpremultiply(data) end
  local png = data:encode("png"):getString()
  local f = outDir and io.open(outDir .. "/" .. name, "wb")
  if f then
    f:write(png)
    f:close()
    print("[media] " .. outDir .. "/" .. name)
  else
    love.filesystem.createDirectory("media")
    love.filesystem.write("media/" .. name, png)
    savedToSaveDir = true
    print("[media] (save dir) media/" .. name)
  end
end

local function render(W, H, fn)
  local canvas = love.graphics.newCanvas(W, H)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  fn(W, H)
  love.graphics.setCanvas()
  return canvas
end

function Media.run()
  love.window.setMode(640, 360, { resizable = false, vsync = 0 })
  love.graphics.setLineStyle("smooth")

  Assets = require("src.assets")
  Shaders = require("src.shaders")
  Background = require("src.background")
  UI = require("src.ui")
  Player = require("src.entities.player")
  Boss = require("src.entities.boss")
  Enemy = require("src.entities.enemy")
  Assets.load()
  Shaders.load()
  Background.load()
  UI.load()

  local src = love.filesystem.getSource()
  if love.filesystem.getRealDirectory("main.lua") == src then outDir = src .. "/media" end

  save("cover.png", render(1260, 1000, function(W, H)
    local L = logoLayout(W * 0.78, true)
    local y = math.floor(H * 0.04)
    -- The scene starts below the logo, which sits on a darkened band.
    drawScene(W, H, setmetatable({ skyX = 0, skyY = 0.5, top = (y + L.h) / H * 0.8 },
      { __index = SCENE }))
    local g = love.graphics
    local band = (y + L.h) * 1.35
    for i = 0, 63 do
      g.setColor(0, 0, 0, 0.5 * (1 - i / 64))
      g.rectangle("fill", 0, i * band / 64, W, band / 64 + 1)
    end
    drawLogo(L, W * 0.5, y)
  end))

  -- Canvas sized to the logo plus room for its glow.
  local LW, PAD = 1200, 48
  local L = logoLayout(LW - PAD * 2, true)
  save("logo.png", render(LW, L.h + PAD * 2, function(W)
    drawLogo(L, W * 0.5, PAD)
  end), true)

  save("fanart.png", render(1920, 1080, function(W, H)
    drawScene(W, H, setmetatable({ skyX = 0, skyY = 0.5 }, { __index = SCENE }))
  end))

  if savedToSaveDir then
    print("[media] media/ not writable next to main.lua; files are in " ..
      love.filesystem.getSaveDirectory() .. "/media")
  end
end

return Media
