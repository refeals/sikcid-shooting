-- Post-processing. For now: the selective glow (bloom) layer.
--
-- Only what should emit light is drawn into the glow layer: shots, sparks,
-- engine flames, rings, pickups, door lamps... (each entity's :drawGlow).
-- The nebula, planets and the HUD never enter it, so they don't bloom.
--
-- The layer lives in small canvases of a FIXED size in logical resolution
-- (Config.FX.glow.<quality>.scale of 640x360), so its cost does not grow with
-- the window. Per frame:
--   1. Post.beginGlow(): emitters draw additively into `a`, in logical
--      coordinates (the same transform as the arena, shake included);
--   2. Post.endGlow(): separable gaussian blur a -> b -> a; on "high", `a` is
--      also downsampled into a half-size level and blurred again (the wide
--      halo); then both are added on top of the current canvas, stretched.
--
-- Without the shader (failed compile, or --fx off) the blur is skipped and
-- `a` is added as is: the linear upscale alone already softens it. The game
-- never depends on the shaders compiling.

local Config = require("src.config")
local Screen = require("src.screen")
local Profiler = require("src.profiler")

local FX = Config.FX
local VW, VH = Config.VIRTUAL_W, Config.VIRTUAL_H

local Post = {
  quality = "high",   -- resolved from Config.FX.quality in Post.load()
  blurOk = false,     -- the blur/gain shaders compiled
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

-- Composite: the glow is premultiplied and may be pushed above 1x.
local GAIN_SRC = [[
uniform float gain;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    return Texel(tex, uv) * gain;
}
]]

local blur, gain
local a, b          -- tight glow level and its blur scratch
local wa, wb        -- wide level (high quality only)
local gs = 1        -- glow canvas px per logical px
local target        -- canvas active when beginGlow() ran
local dirBuf = { 0, 0 }

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

function Post.load()
  Post.quality = resolveQuality()
  -- "off" still uses the layer, just unblurred (the shader-less fallback).
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

  Post.blurOk = false
  if Post.quality ~= "off" then
    local ok1, s1 = pcall(love.graphics.newShader, BLUR_SRC)
    local ok2, s2 = pcall(love.graphics.newShader, GAIN_SRC)
    if ok1 and ok2 then
      blur, gain = s1, s2
      Post.blurOk = true
    else
      print("[post] glow blur unavailable: " .. tostring(ok1 and s2 or s1))
    end
  end
  print(string.format("[post] glow %s (%dx%d%s%s)", Post.quality, a:getWidth(), a:getHeight(),
    wa and ", wide" or "", Post.blurOk and "" or ", no blur"))
end

-- Starts the glow layer. Everything drawn until Post.endGlow() is additive
-- light, in logical coordinates. Emitters must not change the blend mode.
function Post.beginGlow()
  local g = love.graphics
  Profiler.start("glow")
  target = g.getCanvas()
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
local function composite(c, k, tw, th)
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

  g.setCanvas(target)
  local tw, th
  if target then tw, th = target:getDimensions() else tw, th = g.getDimensions() end
  g.setBlendMode("add", "premultiplied")
  if Post.blurOk then
    composite(a, FX.glow.intensity, tw, th)
    if wa then composite(wa, FX.glow.wideIntensity, tw, th) end
  else
    composite(a, 1, tw, th)
  end
  g.pop()
  Profiler.stop("glow")
end

return Post
