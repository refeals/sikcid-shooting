-- The sky behind the arena and the menus: nebula, three drifting star layers
-- with parallax, a planet per theme, distant objects, sparkles, shooting
-- stars, and the arena grid with ripples.
--
-- Ambient motion is a pure function of the clock and fixed seeds:
-- star positions wrap around the screen as they drift, and sparkles, shooting
-- stars and distant objects come from time slots hashed into a position, a
-- sprite and a path. So the lobby and the game over animate with no update,
-- and nothing is allocated per frame. Only three things keep state, all fed
-- by the game screen: the parallax offset (Background.update), the palette
-- fade (Background.setTheme) and the grid ripples (Background.pulse).
--
-- Palette: Config.ART.background.themes, one per `themeEvery` waves.

local Config = require("src.config")
local Assets = require("src.assets")

local Background = {}

local B = Config.ART.background
local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
local MARGIN = 8                       -- stars wrap this far outside the screen
local WRAP_W, WRAP_H = W + MARGIN * 2, H + MARGIN * 2

local sin, cos, floor, pi, sqrt = math.sin, math.cos, math.floor, math.pi, math.sqrt
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Clock since boot: keeps the hashed time slots and the drift in small numbers.
local t0 = 0
local function clock() return love.timer.getTime() - t0 end

local driftX, driftY                   -- normalized drift direction
local layers = {}                      -- [layer] = { stars = {...}, def = B.layers[i] }
local nebulaImages = {}                -- two baked cloud textures
local pixel                            -- 1x1 white image the grid shader is drawn on
local gridArea                         -- area whose origin/size the shader last got
local gridShader

-- Parallax: offset (logical px) of the players from the arena center, eased.
-- Each layer moves against it by its `parallax` factor.
local focusX, focusY = 0, 0

-- Theme fade: `cur` is what gets drawn, lerped from `from` to `to`.
local KEYS = { "bg", "nebulaA", "nebulaB", "star", "obj", "grid" }
local cur, from = {}, {}
local to = B.themes[1]
local themeIndex = 1
local fadeStart = -math.huge
-- Planets cross-fade along with the palette: `fadeK` goes 0 -> 1 from the
-- old theme's planet to the new one's.
local fromTheme = 1
local fadeK = 1
local planetImages = {}                -- [theme index] = baked Image (premultiplied)

-- Grid ripples: fixed slots, the oldest is overwritten.
local PULSE_SLOTS = 4
local pulses = {}                      -- { x, y, strength, start }
local pulseUniform = {}                -- { x, y, radius, strength } per slot, sent to the shader

-- Deterministic 0..1 value for an integer `n` and a channel `k`.
local function hash(n, k)
  local v = sin(n * 12.9898 + k * 78.233 + B.seed * 0.137) * 43758.5453
  return v - floor(v)
end

local function lerp(a, b, t) return a + (b - a) * t end

-- ---------------------------------------------------------------------------
-- Build (Background.load, once at boot)
-- ---------------------------------------------------------------------------
local function buildStars()
  local rng = love.math.newRandomGenerator(B.seed)
  for li, def in ipairs(B.layers) do
    local stars = {}
    for i = 1, def.count do
      local big = rng:random() < def.bigShare
      stars[i] = {
        x = rng:random() * WRAP_W,
        y = rng:random() * WRAP_H,
        size = big and lerp(def.bigMin, def.bigMax, rng:random())
                   or lerp(def.tinyMin, def.tinyMax, rng:random()),
        alpha = lerp(def.alphaMin, def.alphaMax, rng:random()),
        sprite = big and "starSmall" or "starTiny",
        twinkle = rng:random() < B.twinkleShare,
        phase = rng:random() * pi * 2,
        rot = rng:random() * pi * 2,
      }
    end
    layers[li] = { stars = stars, def = def }
  end
end

-- Cloud texture: fractal noise thresholded into wisps, weighted so the edges
-- of the screen carry more nebula than the center. White, alpha = density.
local function bakeNebula(seed)
  local N = B.nebula
  local tw, th = N.texW, N.texH
  local data = love.image.newImageData(tw, th)
  local ox, oy = seed * 17.31, seed * 9.77
  data:mapPixel(function(x, y)
    local u, v = x / tw, y / th
    local n, amp, freq, total = 0, 1, 3, 0
    for _ = 1, 4 do
      n = n + amp * love.math.noise(u * freq * (tw / th) + ox, v * freq + oy)
      total = total + amp
      amp, freq = amp * 0.5, freq * 2
    end
    n = n / total
    local d = math.max(0, math.min(1, (n - 0.38) / 0.5))
    d = d * d
    -- Distance from the center, 0 at the middle, ~1 at the corners.
    local dx, dy = (u - 0.5) * 2, (v - 0.5) * 2
    local r = math.min(1, sqrt(dx * dx * 0.7 + dy * dy * 0.7))
    local edge = 0.25 + 0.75 * r * r
    return 1, 1, 1, d * edge
  end)
  local img = love.graphics.newImage(data)
  img:setFilter("linear", "linear")
  return img
end

-- Grid drawn procedurally over the arena: 1px lines every `cell`, plus rings
-- that brighten the lines (and faintly the space between them) as they pass.
local GRID_SRC = [[
uniform vec2 origin;
uniform vec2 size;
uniform float cell;
uniform float baseAlpha;
uniform float pulseWidth;
uniform float pulseFill;
uniform vec3 pulseColor;
uniform vec4 pulses[4];

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec2 cellPos = uv * size;
    vec2 m = mod(cellPos, cell);
    float line = (m.x < 1.0 || m.y < 1.0) ? 1.0 : 0.0;
    vec2 p = origin + cellPos;
    float glow = 0.0;
    for (int i = 0; i < 4; i++) {
        vec4 q = pulses[i];
        float d = abs(length(p - q.xy) - q.z);
        glow += q.w * (1.0 - smoothstep(0.0, pulseWidth, d));
    }
    // The ring tints the dim grid color toward the bright star color.
    vec3 rgb = mix(color.rgb, pulseColor, clamp(glow * 1.6, 0.0, 1.0));
    float a = line * (baseAlpha + glow) + glow * pulseFill;
    return vec4(rgb, color.a * min(a, 1.0));
}
]]

-- Planets: each theme's planet is stacked from Kenney Planets parts on a
-- canvas (tinted sphere, tinted surface patterns, light map multiplied on
-- top, its lit side turned toward the screen center) and kept as an Image.
-- The canvas holds premultiplied colors, so the result is drawn in
-- premultiplied mode. A missing part only costs that theme its planet.
local function bakePlanets()
  local P = B.planets
  local parts = {}   -- name -> Image, or false if it failed to load
  local function part(name)
    if parts[name] == nil then
      local ok, img = pcall(love.graphics.newImage, P.dir .. name .. ".png")
      parts[name] = ok and img or false
      if not ok then print(string.format("[background] planet part '%s' not found", name)) end
    end
    return parts[name] or nil
  end

  local size = P.bake
  local half = size * 0.5
  local canvas = love.graphics.newCanvas(size, size)
  local function stamp(img, rot)
    local k = size / img:getWidth()
    love.graphics.draw(img, half, half, rot or 0, k, k, img:getWidth() * 0.5, img:getHeight() * 0.5)
  end

  for i, theme in ipairs(B.themes) do
    local def = theme.planet
    local sphere, light = def and part(def.sphere), def and part(def.light)
    local ok = sphere and light
    if ok then
      for _, layer in ipairs(def.layers) do
        if not part(layer[1]) then ok = false end
      end
    end
    if ok then
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setBlendMode("alpha")
      love.graphics.setColor(def.base[1], def.base[2], def.base[3], 1)
      stamp(sphere)
      for _, layer in ipairs(def.layers) do
        local c = layer[2]
        love.graphics.setColor(c[1], c[2], c[3], layer[3])
        stamp(parts[layer[1]], layer[4])
      end
      local lit = atan2(H * 0.5 - def.y, W * 0.5 - def.x)
      love.graphics.setBlendMode("multiply", "premultiplied")
      love.graphics.setColor(1, 1, 1, 1)
      stamp(light, lit - (P.lightDir[def.light] or 0))
      love.graphics.setBlendMode("alpha")
      love.graphics.setCanvas()

      local img = love.graphics.newImage(canvas:newImageData(), { mipmaps = true })
      img:setFilter("linear", "linear")
      img:setMipmapFilter("linear")
      planetImages[i] = img
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  canvas:release()
  for _, img in pairs(parts) do
    if img then img:release() end
  end
end

function Background.load()
  t0 = love.timer.getTime()
  local len = sqrt(B.drift[1] ^ 2 + B.drift[2] ^ 2)
  driftX, driftY = B.drift[1] / len, B.drift[2] / len
  buildStars()
  nebulaImages[1] = bakeNebula(1)
  nebulaImages[2] = bakeNebula(2)
  bakePlanets()

  local d = love.image.newImageData(1, 1)
  d:setPixel(0, 0, 1, 1, 1, 1)
  pixel = love.graphics.newImage(d)

  local ok, shader = pcall(love.graphics.newShader, GRID_SRC)
  if ok then
    gridShader = shader
    gridShader:send("cell", B.grid.cell)
    gridShader:send("baseAlpha", B.grid.alpha)
    gridShader:send("pulseWidth", B.grid.pulseWidth)
    gridShader:send("pulseFill", B.grid.pulseFill)
  else
    -- Without it the grid is drawn with plain lines and no ripples.
    print("[background] grid shader unavailable: " .. tostring(shader))
  end

  for _, k in ipairs(KEYS) do
    cur[k] = { to[k][1], to[k][2], to[k][3] }
    from[k] = { to[k][1], to[k][2], to[k][3] }
  end
  for i = 1, PULSE_SLOTS do
    pulses[i] = { x = 0, y = 0, strength = 0, start = -math.huge }
    pulseUniform[i] = { 0, 0, 0, 0 }
  end
  print(string.format("[background] ready (%.0f ms)", clock() * 1000))
end

-- ---------------------------------------------------------------------------
-- State fed by the game screen
-- ---------------------------------------------------------------------------

-- Theme for a wave number (waves 1..themeEvery = theme 1, and so on, cycling).
function Background.themeForWave(wave)
  local n = #B.themes
  return (floor((math.max(1, wave) - 1) / B.themeEvery) % n) + 1
end

local function refreshColors(now)
  local t = (now - fadeStart) / B.themeFade
  if t >= 1 then t = 1 elseif t < 0 then t = 0 end
  t = t * t * (3 - 2 * t)
  fadeK = t
  for i = 1, #KEYS do
    local k = KEYS[i]
    local c, a, b = cur[k], from[k], to[k]
    c[1], c[2], c[3] = lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
  end
end

-- Fades the palette to theme `index` (instant = no fade, for a fresh match).
function Background.setTheme(index, instant)
  if index == themeIndex and not instant then return end
  local now = clock()
  refreshColors(now)   -- start from what is on screen, even mid-fade
  for i = 1, #KEYS do
    local k = KEYS[i]
    from[k][1], from[k][2], from[k][3] = cur[k][1], cur[k][2], cur[k][3]
  end
  fromTheme = instant and index or themeIndex
  themeIndex = index
  to = B.themes[index]
  fadeStart = instant and -math.huge or now
  refreshColors(now)
end

-- Starts a grid ripple at (x, y). Strength ~0.3 (soft) .. 0.6 (strong).
function Background.pulse(x, y, strength)
  local slot, oldest = 1, math.huge
  for i = 1, PULSE_SLOTS do
    if pulses[i].start < oldest then slot, oldest = i, pulses[i].start end
  end
  local p = pulses[slot]
  p.x, p.y, p.strength, p.start = x, y, strength, clock()
end

-- Eases the parallax toward the players' center (fx, fy), relative to the
-- point (cx, cy) the sky is centered on. Game screen only.
function Background.update(dt, fx, fy, cx, cy)
  local k = math.min(1, B.parallaxEase * dt)
  focusX = focusX + ((fx - cx) - focusX) * k
  focusY = focusY + ((fy - cy) - focusY) * k
end

-- New match: no parallax, no ripples, palette set straight to `theme`.
function Background.reset(theme)
  focusX, focusY = 0, 0
  for i = 1, PULSE_SLOTS do pulses[i].start = -math.huge end
  Background.setTheme(theme or 1, true)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Current on-screen position of a star (drift + parallax, wrapped).
local function starPos(s, def, t)
  local x = (s.x + driftX * def.speed * t - focusX * def.parallax) % WRAP_W - MARGIN
  local y = (s.y + driftY * def.speed * t - focusY * def.parallax) % WRAP_H - MARGIN
  return x, y
end

local function drawStars(layer, sprite, t)
  local def, stars = layer.def, layer.stars
  local c = cur.star
  for i = 1, #stars do
    local s = stars[i]
    if s.sprite == sprite then
      local a = s.alpha
      if s.twinkle then a = a * (0.45 + 0.55 * (0.5 + 0.5 * sin(t * B.twinkleSpeed + s.phase))) end
      love.graphics.setColor(c[1], c[2], c[3], a)
      local x, y = starPos(s, def, t)
      Assets.draw(sprite, x, y, s.rot, s.size)
    end
  end
end

local function drawNebula(t)
  local N = B.nebula
  local sx, sy = W / N.texW, H / N.texH
  love.graphics.setBlendMode("add")
  for i = 1, 2 do
    local c = i == 1 and cur.nebulaA or cur.nebulaB
    local ph = i * 2.1
    local k = 1.12 + N.breathe * sin(t * N.swayRate * 1.7 + ph)
    local x = W * 0.5 + N.sway * cos(t * N.swayRate + ph)
    local y = H * 0.5 + N.sway * 0.6 * sin(t * N.swayRate * 1.3 + ph)
    love.graphics.setColor(c[1], c[2], c[3], N.alpha)
    -- The second layer is mirrored so the two never line up.
    local flip = i == 1 and 1 or -1
    love.graphics.draw(nebulaImages[i], x, y, 0, sx * k * flip, sy * k, N.texW * 0.5, N.texH * 0.5)
  end
  love.graphics.setBlendMode("alpha")
end

-- Distant objects. Slot j may launch one object at a hashed time inside the
-- slot; it crosses from one edge to the opposite one over its lifetime.
local function drawObjects(t)
  local O = B.objects
  local kinds = O.kinds
  local c = cur.obj
  love.graphics.setColor(c[1], c[2], c[3], 1)
  local slot = floor(t / O.slot)
  local px, py = -focusX * O.parallax, -focusY * O.parallax
  for j = slot - 2, slot do
    if hash(j, 1) < O.chance then
      local kind = kinds[floor(hash(j, 2) * #kinds) + 1]
      local life = lerp(kind.lifeMin, kind.lifeMax, hash(j, 3))
      local start = j * O.slot + hash(j, 4) * O.slot * 0.5
      local p = (t - start) / life
      if p >= 0 and p <= 1 then
        local size = lerp(kind.sizeMin, kind.sizeMax, hash(j, 5))
        local m = size
        -- Entry side (0 left, 1 right, 2 top, 3 bottom), exit on the opposite.
        local side = floor(hash(j, 6) * 4)
        local a, b = hash(j, 7), hash(j, 8)
        local x0, y0, x1, y1
        if side == 0 then x0, y0, x1, y1 = -m, a * H, W + m, b * H
        elseif side == 1 then x0, y0, x1, y1 = W + m, a * H, -m, b * H
        elseif side == 2 then x0, y0, x1, y1 = a * W, -m, b * W, H + m
        else x0, y0, x1, y1 = a * W, H + m, b * W, -m end
        local x, y = lerp(x0, x1, p) + px, lerp(y0, y1, p) + py
        local angle
        if kind.ship then
          angle = atan2(y1 - y0, x1 - x0)
        else
          local dir = hash(j, 9) < 0.5 and -1 or 1
          angle = hash(j, 10) * pi * 2 + dir * kind.spin * (t - start)
        end
        Assets.draw(kind.role, x, y, angle, size)
      end
    end
  end
end

-- Planet of theme `i` at opacity `a` (blend mode set by the caller to
-- premultiplied alpha, which is how the baked image stores its colors).
local function drawPlanet(i, a, t)
  local img = planetImages[i]
  if not img or a <= 0 then return end
  local P, def = B.planets, B.themes[i].planet
  local x = def.x - focusX * P.parallax + P.bob * cos(t * P.bobRate + i)
  local y = def.y - focusY * P.parallax + P.bob * sin(t * P.bobRate * 1.3 + i)
  local k = def.size / img:getWidth()
  local b = P.brightness * a
  love.graphics.setColor(b, b, b, a)
  love.graphics.draw(img, x, y, 0, k, k, img:getWidth() * 0.5, img:getHeight() * 0.5)
end

-- True when (x, y) lies on the current theme's planet disc.
local function behindPlanet(x, y)
  if not planetImages[themeIndex] then return false end
  local def = B.themes[themeIndex].planet
  local dx, dy, r = x - def.x, y - def.y, def.size * 0.5
  return dx * dx + dy * dy < r * r
end

-- Glints: slot i fires every `period` seconds, on a hashed mid/near star.
local function drawSparkles(t)
  local S = B.sparkle
  local c = cur.star
  for i = 1, S.slots do
    local period = lerp(S.periodMin, S.periodMax, hash(i, 11))
    local tt = t + hash(i, 12) * period
    local cycle = floor(tt / period)
    local u = tt - cycle * period
    if u < S.life then
      local layer = layers[hash(cycle * 7 + i, 13) < 0.5 and 2 or 3]
      local stars = layer.stars
      local s = stars[floor(hash(cycle * 7 + i, 14) * #stars) + 1]
      local x, y = starPos(s, layer.def, t)
      if not behindPlanet(x, y) then   -- that star is hidden by the planet
        local k = sin(pi * u / S.life)
        local size = lerp(S.sizeMin, S.sizeMax, hash(cycle * 7 + i, 15)) * k
        love.graphics.setColor(c[1], c[2], c[3], S.alpha * k)
        Assets.draw("starGlint", x, y, s.rot + u * S.spin, size)
      end
    end
  end
end

-- Shooting stars: one per lucky slot, heading roughly along the drift.
local function drawShootingStar(t)
  local S = B.shootingStar
  local j = floor(t / S.slot)
  if hash(j, 21) >= S.chance then return end
  local start = j * S.slot + hash(j, 22) * (S.slot - S.life)
  local p = (t - start) / S.life
  if p < 0 or p > 1 then return end
  local dir = atan2(driftY, driftX) + (hash(j, 23) - 0.5) * S.spread
  local dx, dy = cos(dir), sin(dir)
  local travel = lerp(S.travelMin, S.travelMax, hash(j, 24))
  -- Starts well inside the screen so the whole streak stays in view.
  local x0 = lerp(W * 0.15, W * 0.85, hash(j, 25)) - dx * travel * 0.5
  local y0 = lerp(H * 0.25, H * 0.85, hash(j, 26)) - dy * travel * 0.5
  local hx, hy = x0 + dx * travel * p, y0 + dy * travel * p
  local env = sin(pi * p)
  local len = S.length * math.min(1, p * 3)
  local c = cur.star
  love.graphics.setBlendMode("add")
  love.graphics.setColor(c[1], c[2], c[3], S.alpha * env)
  if len > 1 then
    local streak = Assets.sprite("streak")
    local k = len / math.max(streak.w, streak.h)
    Assets.draw("streak", hx - dx * len * 0.5, hy - dy * len * 0.5, dir, len, S.width / (streak.w * k), 1)
  end
  love.graphics.setColor(1, 1, 1, S.alpha * env)
  Assets.draw("starSmall", hx, hy, 0, 4)
  love.graphics.setBlendMode("alpha")
end

-- The whole sky, covering the 640x360 screen (in game the HUD hides its top).
function Background.draw()
  local t = clock()
  refreshColors(t)

  local bg = cur.bg
  love.graphics.setColor(bg[1], bg[2], bg[3], 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  for li = 1, #layers do
    drawStars(layers[li], "starTiny", t)
    drawStars(layers[li], "starSmall", t)
  end
  -- Opaque planet over the stars (they are behind it), veiled by the nebula
  -- drawn on top, so it sits back in the sky. Objects pass in front.
  love.graphics.setBlendMode("alpha", "premultiplied")
  if fadeK < 1 and fromTheme ~= themeIndex then drawPlanet(fromTheme, 1 - fadeK, t) end
  drawPlanet(themeIndex, fadeK, t)
  love.graphics.setBlendMode("alpha")
  drawNebula(t)
  drawObjects(t)
  love.graphics.setBlendMode("add")
  drawSparkles(t)
  love.graphics.setBlendMode("alpha")
  drawShootingStar(t)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Arena grid over the sky, with the active ripples. `area` = {x, y, w, h}.
function Background.drawGrid(area)
  local G = B.grid
  local c = cur.grid
  if not gridShader then
    love.graphics.setColor(c[1], c[2], c[3], G.alpha)
    for gx = area.x + G.cell, area.x + area.w - 1, G.cell do
      love.graphics.line(gx + 0.5, area.y, gx + 0.5, area.y + area.h)
    end
    for gy = area.y + G.cell, area.y + area.h - 1, G.cell do
      love.graphics.line(area.x, gy + 0.5, area.x + area.w, gy + 0.5)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local now = clock()
  for i = 1, PULSE_SLOTS do
    local p, u = pulses[i], pulseUniform[i]
    local age = now - p.start
    if age >= 0 and age < G.pulseLife then
      local fade = 1 - age / G.pulseLife
      u[1], u[2], u[3], u[4] = p.x, p.y, age * G.pulseSpeed, p.strength * fade
    else
      u[1], u[2], u[3], u[4] = 0, 0, 0, 0
    end
  end
  gridShader:send("pulses", pulseUniform[1], pulseUniform[2], pulseUniform[3], pulseUniform[4])
  gridShader:send("pulseColor", cur.star)
  if area ~= gridArea then   -- the arena never changes: sent once
    gridArea = area
    gridShader:send("origin", { area.x, area.y })
    gridShader:send("size", { area.w, area.h })
  end

  love.graphics.setShader(gridShader)
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.draw(pixel, area.x, area.y, 0, area.w, area.h)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
end

return Background
