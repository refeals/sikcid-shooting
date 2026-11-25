-- Post-processing: the selective glow (bloom) layer and the scene composite
-- (shockwaves, chromatic aberration, vignette).
--
-- Arena frame, as Game:draw runs it:
--   Post.beginScene()          -- the arena draws into `scene`, not the screen
--     ...sky, grid, entities...
--     Post.beginGlow() ... Post.endGlow()   -- light, added into the scene
--   Post.endScene()            -- scene -> screen canvas through the composite
--   ...banners, texts, HUD     -- sharp, never distorted
--
-- Glow: only what should emit light is drawn into it (each entity's
-- :drawGlow). It lives in small canvases of a FIXED size in logical
-- resolution (Config.FX.glow.<quality>.scale of 640x360), so its cost does
-- not grow with the window: emitters draw additively into `a`, a separable
-- gaussian blurs a -> b -> a (on "high" also a half-size level for a wide
-- halo), and both are added on top of the current canvas, stretched.
--
-- Scene composite: one full-screen pass with up to 4 shockwave rings
-- (radial displacement), a radial RGB split and the arena vignette. Their
-- state runs on game time (Post.update), so it freezes in hit-stop and goes
-- slow in the game over slow motion.
--
-- Without the shaders (failed compile, or --fx off) the blur is skipped (the
-- glow is added as is: the linear upscale alone softens it) and the scene
-- pass is skipped (the arena draws straight to the screen). The game never
-- depends on the shaders compiling.

local Config = require("src.config")
local Screen = require("src.screen")
local Profiler = require("src.profiler")

local FX = Config.FX
local VW, VH = Config.VIRTUAL_W, Config.VIRTUAL_H

local Post = {
  quality = "high",   -- resolved from Config.FX.quality in Post.load()
  blurOk = false,     -- the blur/gain shaders compiled
  sceneOk = false,    -- the composite shader compiled
}

-- 9-tap gaussian with linear sampling: 5 fetches along `direction` (one
-- texel step, already scaled by the spread). Constant offsets, no loops:
-- valid GLSL ES 1.0 for love.js/WebGL1.
local BLUR_SRC = [[
uniform vec2 direction;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec2 o1 = direction * 1.3846153846;
    vec2 o2 = direction * 3.2307692308;
    vec4 s = Texel(tex, uv) * 0.2270270270;
    s += (Texel(tex, uv + o1) + Texel(tex, uv - o1)) * 0.3162162162;
    s += (Texel(tex, uv + o2) + Texel(tex, uv - o2)) * 0.0702702703;
    return s * color;
}
]]

-- Glow composite: the glow is premultiplied and may be pushed above 1x.
local GAIN_SRC = [[
uniform float gain;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    return Texel(tex, uv) * gain;
}
]]

-- Scene composite. All distances in logical px (640x360). The 4 waves are
-- unrolled (no dynamic indexing, WebGL1-safe); an idle wave has strength 0.
local SCENE_SRC = [[
uniform vec4 waves[4];     // x, y, ring radius, strength
uniform vec4 waveWidth;    // ring half-width of each wave
uniform vec2 logical;      // logical screen size
uniform vec2 center;       // arena center
uniform vec2 halfSize;     // arena half size
uniform float aberration;  // RGB split at the arena side edges
uniform vec3 vignette;     // strength, inner, outer
uniform vec4 tint;         // vignette tint rgb + amount

// Signed bump around the ring: pulls in just inside it, pushes out just
// outside, so the ring reads as a lens sweeping outward.
vec2 shock(vec2 p, vec4 w, float width)
{
    vec2 d = p - w.xy;
    float dist = max(length(d), 0.0001);
    float x = (dist - w.z) / width;
    return d / dist * (w.w * x * exp(-x * x * 2.0));
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec2 p = uv * logical;
    vec2 q = p - shock(p, waves[0], waveWidth.x) - shock(p, waves[1], waveWidth.y)
               - shock(p, waves[2], waveWidth.z) - shock(p, waves[3], waveWidth.w);
    vec2 uq = q / logical;
    vec2 ca = (q - center) / halfSize.x * aberration / logical;
    vec3 c = vec3(Texel(tex, uq + ca).r, Texel(tex, uq).g, Texel(tex, uq - ca).b);
    float v = smoothstep(vignette.y, vignette.z, length((p - center) / halfSize));
    c *= 1.0 - vignette.x * v;
    c = mix(c, tint.rgb, tint.a * v);
    return vec4(c, 1.0);
}
]]

local blur, gain, composite
local a, b          -- tight glow level and its blur scratch
local wa, wb        -- wide level (high quality only)
local gs = 1        -- glow canvas px per logical px
local glowTarget    -- canvas active when beginGlow() ran
local dirBuf = { 0, 0 }

local scene         -- same size as Screen.canvas, (re)made on demand
local sceneTarget   -- canvas active when beginScene() ran
local sceneActive = false

-- Effect state (game time).
local WAVE_SLOTS = 4
local waves = {}
for i = 1, WAVE_SLOTS do
  waves[i] = { x = 0, y = 0, t = 1, life = 1, radius = 0, strength = 0, width = 1 }
end
local aberration = 0
local hurt = 0

-- Uniform buffers, reused every frame (no per-frame allocation).
local waveBuf = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
local widthBuf = { 1, 1, 1, 1 }
local tintBuf = { 0, 0, 0, 0 }
local centerBuf, halfBuf = { 0, 0 }, { 1, 1 }

local function newLevel(w, h)
  local c = love.graphics.newCanvas(math.max(1, math.floor(w)), math.max(1, math.floor(h)))
  c:setFilter("linear", "linear")
  return c
end

local function resolveQuality()
  local q = FX.quality
  if q == "auto" then q = Config.WEB and "low" or "high" end
  if q ~= "high" and q ~= "low" and q ~= "off" then q = "high" end
  return q
end

local function compile(name, src)
  local ok, shader = pcall(love.graphics.newShader, src)
  if ok then return shader end
  print("[post] " .. name .. " unavailable: " .. tostring(shader))
  return nil
end

function Post.load()
  Post.quality = resolveQuality()
  -- "off" still uses the glow layer, just unblurred (the shader-less path).
  local preset = FX.glow[Post.quality == "off" and "low" or Post.quality]
  gs = preset.scale
  a = newLevel(VW * gs, VH * gs)
  b = newLevel(VW * gs, VH * gs)
  if preset.wide then
    wa = newLevel(VW * gs * 0.5, VH * gs * 0.5)
    wb = newLevel(VW * gs * 0.5, VH * gs * 0.5)
  else
    wa, wb = nil, nil
  end

  blur, gain, composite = nil, nil, nil
  if Post.quality ~= "off" then
    local s1, s2 = compile("glow blur", BLUR_SRC), compile("glow gain", GAIN_SRC)
    if s1 and s2 then blur, gain = s1, s2 end
    composite = compile("scene composite", SCENE_SRC)
  end
  Post.blurOk = blur ~= nil
  Post.sceneOk = composite ~= nil
  if composite then
    local V = FX.vignette
    composite:send("logical", { VW, VH })
    composite:send("vignette", { V.strength, V.inner, V.outer })
  end
  print(string.format("[post] %s: glow %dx%d%s%s, scene %s", Post.quality,
    a:getWidth(), a:getHeight(), wa and " + wide" or "", Post.blurOk and "" or " (no blur)",
    Post.sceneOk and "on" or "off"))
end

-- Particle pool size for the current quality (Config.FX.particles).
function Post.particleCap()
  return FX.particles[Post.quality == "high" and "high" or "low"]
end

-- ---------------------------------------------------------------------------
-- Effects (game time)
-- ---------------------------------------------------------------------------

-- A shockwave ring from (x, y) with a Config.FX.shock preset. `radius`
-- overrides the preset's final radius (to match a gameplay radius). Takes a
-- free slot, or the one closest to its end.
function Post.shockwave(x, y, preset, radius)
  local slot, left = 1, math.huge
  for i = 1, WAVE_SLOTS do
    local w = waves[i]
    local l = w.life - w.t
    if l < left then slot, left = i, l end
  end
  local w = waves[slot]
  w.x, w.y, w.t, w.life = x, y, 0, preset.life
  w.radius = radius or preset.radius
  w.strength, w.width = preset.strength, preset.width
end

-- RGB split pulse (px at the arena side edges); the strongest one wins.
function Post.aberrate(amount)
  local AB = FX.aberration
  aberration = math.min(AB.max, math.max(aberration, amount))
end

-- Red vignette pulse (0..1 of Config.FX.vignette.hurt).
function Post.hurt(amount)
  hurt = math.max(hurt, amount or 1)
end

function Post.update(dt)
  for i = 1, WAVE_SLOTS do
    local w = waves[i]
    if w.t < w.life then w.t = math.min(w.life, w.t + dt) end
  end
  if aberration > 0 then aberration = math.max(0, aberration - FX.aberration.decay * dt) end
  if hurt > 0 then hurt = math.max(0, hurt - FX.vignette.hurtDecay * dt) end
end

function Post.clear()
  for i = 1, WAVE_SLOTS do
    local w = waves[i]
    w.t, w.life, w.strength = 1, 1, 0
  end
  aberration, hurt = 0, 0
end

-- ---------------------------------------------------------------------------
-- Scene pass
-- ---------------------------------------------------------------------------

-- Redirects the arena into `scene`. The current transform (shake + render
-- scale) stays as it is, so everything draws exactly as on the screen.
function Post.beginScene()
  if not Post.sceneOk then return end
  local g = love.graphics
  local sc = Screen.canvas
  local w, h = sc:getDimensions()
  if not scene or scene:getWidth() ~= w or scene:getHeight() ~= h then
    if scene then scene:release() end
    scene = g.newCanvas(w, h)
    scene:setFilter("linear", "linear")   -- distortion samples between texels
  end
  sceneTarget = g.getCanvas()
  g.setCanvas(scene)
  g.clear(Config.COLORS.bg)
  sceneActive = true
end

local function sendEffects(arena)
  for i = 1, WAVE_SLOTS do
    local w, buf = waves[i], waveBuf[i]
    local k = w.t / w.life
    local out = 1 - (1 - k) * (1 - k)          -- ease-out growth
    buf[1], buf[2] = w.x, w.y
    buf[3] = w.radius * out
    buf[4] = k < 1 and w.strength * (1 - k) * (1 - k) or 0
    widthBuf[i] = w.width * (0.6 + 0.4 * k)
  end
  composite:send("waves", waveBuf[1], waveBuf[2], waveBuf[3], waveBuf[4])
  composite:send("waveWidth", widthBuf)
  centerBuf[1], centerBuf[2] = arena.x + arena.w * 0.5, arena.y + arena.h * 0.5
  halfBuf[1], halfBuf[2] = arena.w * 0.5, arena.h * 0.5
  composite:send("center", centerBuf)
  composite:send("halfSize", halfBuf)
  composite:send("aberration", aberration)
  local V = FX.vignette
  tintBuf[1], tintBuf[2], tintBuf[3] = V.hurtColor[1], V.hurtColor[2], V.hurtColor[3]
  tintBuf[4] = hurt * V.hurt
  composite:send("tint", tintBuf)
end

-- Draws `scene` onto the canvas that was active before, through the
-- composite. `arena` ({x, y, w, h}) centers the aberration and vignette.
function Post.endScene(arena)
  if not sceneActive then return end
  sceneActive = false
  Profiler.start("post")
  local g = love.graphics
  sendEffects(arena)
  -- Back to the screen canvas BEFORE the push, so the pop keeps it (the
  -- HUD draws there next).
  g.setCanvas(sceneTarget)
  g.push("all")
  g.origin()
  g.setShader(composite)
  g.setBlendMode("replace", "premultiplied")
  g.setColor(1, 1, 1, 1)
  g.draw(scene, 0, 0)
  g.pop()
  Profiler.stop("post")
end

-- ---------------------------------------------------------------------------
-- Glow layer
-- ---------------------------------------------------------------------------

-- Starts the glow layer. Everything drawn until Post.endGlow() is additive
-- light, in logical coordinates. Emitters must not change the blend mode.
function Post.beginGlow()
  local g = love.graphics
  Profiler.start("post")
  glowTarget = g.getCanvas()
  g.push("all")
  g.setCanvas(a)
  g.clear(0, 0, 0, 0)
  g.origin()
  -- Same whole-px shake as the arena (Screen.beginDraw), at glow scale.
  g.translate(math.floor(Screen.shakeX) * gs, math.floor(Screen.shakeY) * gs)
  g.scale(gs, gs)
  g.setShader()
  g.setBlendMode("add")
  g.setColor(1, 1, 1, 1)
end

-- One blur pass: src -> dst (same size, or a downsample), along (dx, dy).
local function pass(src, dst, dx, dy)
  local g = love.graphics
  g.setCanvas(dst)
  g.clear(0, 0, 0, 0)
  local sw, sh = src:getDimensions()
  dirBuf[1], dirBuf[2] = dx * FX.glow.spread / sw, dy * FX.glow.spread / sh
  blur:send("direction", dirBuf)
  local dw, dh = dst:getDimensions()
  g.draw(src, 0, 0, 0, dw / sw, dh / sh)
end

-- Adds `c` on top of the target canvas, stretched to cover it.
local function addLevel(c, k, tw, th)
  local g = love.graphics
  if gain then
    gain:send("gain", k)
    g.setShader(gain)
  else
    g.setShader()
  end
  local cw, ch = c:getDimensions()
  g.draw(c, 0, 0, 0, tw / cw, th / ch)
end

function Post.endGlow()
  local g = love.graphics
  g.pop()
  g.push("all")
  g.origin()
  g.setColor(1, 1, 1, 1)

  if Post.blurOk then
    g.setBlendMode("replace", "premultiplied")
    g.setShader(blur)
    pass(a, b, 1, 0)
    pass(b, a, 0, 1)
    if wa then
      pass(a, wb, 1, 0)   -- downsample + horizontal in one go
      pass(wb, wa, 0, 1)
    end
  end

  g.setCanvas(glowTarget)
  local tw, th
  if glowTarget then tw, th = glowTarget:getDimensions() else tw, th = g.getDimensions() end
  g.setBlendMode("add", "premultiplied")
  if Post.blurOk then
    addLevel(a, FX.glow.intensity, tw, th)
    if wa then addLevel(wa, FX.glow.wideIntensity, tw, th) end
  else
    addLevel(a, 1, tw, th)
  end
  g.pop()
  Profiler.stop("post")
end

return Post
