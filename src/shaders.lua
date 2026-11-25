-- Sprite shaders: the palette swap for player-owned art and the boss's
-- energy shield. (Full-screen effects live in src/post.lua.)
--
-- Kenney's spaceShooter2 ships and missiles are red + white + steel. The
-- "recolor" shader finds the red texels (red channel well above green/blue)
-- and replaces their hue with a target color, keeping their brightness so
-- highlights and shadows survive. White, grey, steel and the purple cockpit
-- are left alone. The draw color still multiplies the result, so alpha fades
-- (respawn blink, etc.) keep working.

local Config = require("src.config")
local Assets = require("src.assets")

local Shaders = {}

local RECOLOR_SRC = [[
uniform vec3 target;
uniform float redMin;
uniform float redMax;
uniform float baseRed;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec4 t = Texel(tex, uv);
    float redness = t.r - max(t.g, t.b);
    float w = smoothstep(redMin, redMax, redness);
    vec3 swapped = clamp(target * (t.r / baseRed), 0.0, 1.0);
    return vec4(mix(t.rgb, swapped, w), t.a) * color;
}
]]

-- Dissolve (Config.FX.dissolve): a sprite appearing (or vanishing) through
-- a threshold on a pattern, with a glowing `edge` color at the front.
-- `progress` 0 = gone, 1 = whole. The pattern (0..1 per texel) is:
--   mode 0 -- value noise over the sprite's UV (each sprite is its own
--             image, so UV 0..1 is the sprite);
--   mode 1 -- a sweep along `down`, the world's "down" written in the
--             sprite's UV space, so a rotated ship still builds top to bottom.
-- `recolor` > 0.5 also applies the player palette swap (same math as
-- RECOLOR_SRC) so a player ship keeps its color while it builds.
local DISSOLVE_SRC = [[
uniform float progress;
uniform vec3 edge;
uniform float edgeWidth;
uniform float noiseScale;
uniform float mode;
uniform vec2 down;
uniform float recolor;
uniform vec3 target;
uniform float redMin;
uniform float redMax;
uniform float baseRed;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec4 t = Texel(tex, uv);
    if (recolor > 0.5) {
        float redness = t.r - max(t.g, t.b);
        float w = smoothstep(redMin, redMax, redness);
        t.rgb = mix(t.rgb, clamp(target * (t.r / baseRed), 0.0, 1.0), w);
    }
    t *= color;
    float n;
    if (mode < 0.5) {
        n = vnoise(uv * noiseScale) * 0.65 + vnoise(uv * noiseScale * 2.7) * 0.35;
    } else {
        n = clamp(dot(uv - 0.5, down) * 0.85 + 0.5, 0.0, 1.0);
    }
    // The threshold runs a bit past both ends so 0 and 1 are fully off/on.
    float thr = progress * (1.0 + edgeWidth);
    if (n > thr) return vec4(0.0);
    float e = smoothstep(thr - edgeWidth, thr, n) * step(progress, 0.999);
    return vec4(mix(t.rgb, edge, e), t.a);
}
]]

-- Sheen (Config.FX.pickup): redraws an image as pure white only inside a
-- diagonal band (along uv.x + uv.y, centered on `pos`, `width` wide with
-- soft edges), masked by the image's own alpha. Drawn additively over the
-- original, it reads as a glint sweeping across it.
local SHEEN_SRC = [[
uniform float pos;
uniform float width;
uniform float screenMode;   // 1 = band in screen px (texts: glyph UVs are atlas UVs)
uniform float center;       // screenMode: band center along screen.x + screen.y * 0.4
uniform float bandPx;       // screenMode: band width in px

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    float band;
    if (screenMode > 0.5) {
        float d = abs(screen.x + screen.y * 0.4 - center);
        band = 1.0 - smoothstep(bandPx * 0.3, bandPx * 0.5, d);
    } else {
        float d = abs((uv.x + uv.y) * 0.5 - pos);
        band = 1.0 - smoothstep(width * 0.3, width * 0.5, d);
    }
    return vec4(1.0, 1.0, 1.0, Texel(tex, uv).a * band * color.a);
}
]]

-- Boss energy shield (Config.BOSS.shield), drawn on a 1x1 white image
-- stretched over the shield's square, so `uv` spans it 0..1. A fresnel rim,
-- a faint drifting hex grid, and up to 4 impact ripples (`hits`: local x, y
-- in -1..1, age 0..1 where >= 1 is idle, strength), unrolled for WebGL1.
-- The draw color's alpha fades the whole shield.
local SHIELD_SRC = [[
uniform vec3 tint;
uniform float time;
uniform float hexScale;
uniform vec3 look;        // rim alpha, hex alpha, fill alpha
uniform vec4 hits[4];

const vec2 HEX = vec2(1.0, 1.7320508);

// Distance to the nearest hex cell edge (0 on the edge, 0.5 at the center).
float hexEdge(vec2 p)
{
    vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / HEX.xyxy) + 0.5;
    vec4 h = vec4(p - hc.xy * HEX, p - (hc.zw + 0.5) * HEX);
    vec2 g = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
    g = abs(g);
    return 0.5 - max(dot(g, HEX * 0.5), g.x);
}

// An impact: a bright spot that fades while a ripple ring spreads from it.
float ripple(vec2 p, vec4 h)
{
    if (h.z >= 1.0) return 0.0;
    float d = distance(p, h.xy);
    float k = 1.0 - h.z;
    float ring = (d - h.z * 0.7) / 0.12;
    return h.w * k * (exp(-ring * ring) + k * exp(-d * d / 0.02));
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    vec2 p = uv * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.0) return vec4(0.0);
    float rim = smoothstep(0.55, 1.0, r);
    rim *= rim;
    float hex = 1.0 - smoothstep(0.0, 0.07, hexEdge(p * hexScale + vec2(0.0, time * 0.35)));
    hex *= 0.7 + 0.3 * sin(time * 3.0 + p.y * 5.0);
    float hit = ripple(p, hits[0]) + ripple(p, hits[1]) + ripple(p, hits[2]) + ripple(p, hits[3]);
    float a = look.z + look.x * rim + look.y * hex * (0.35 + rim) + hit;
    a *= 1.0 - smoothstep(0.97, 1.0, r);    // soft outer edge
    vec3 c = mix(tint, vec3(1.0), clamp(hit, 0.0, 1.0) * 0.4);
    return vec4(c, clamp(a, 0.0, 1.0)) * color;
}
]]

local recolor
local shield
local dissolve
local sheen
local currentTarget = { -1, -1, -1 }
local tintBuf = { 1, 1, 1 }
local edgeBuf, downBuf, targetBuf = { 1, 1, 1 }, { 0, 1 }, { 1, 1, 1 }

function Shaders.load()
  local okH, h = pcall(love.graphics.newShader, SHEEN_SRC)
  if okH then
    h:send("width", Config.FX.pickup.sheenWidth)
    sheen = h
  else
    -- Without it the pickups simply have no glint.
    print("[shaders] sheen unavailable: " .. tostring(h))
  end

  local okD, d = pcall(love.graphics.newShader, DISSOLVE_SRC)
  if okD then
    local D, p = Config.FX.dissolve, Config.ART.recolor
    d:send("edgeWidth", D.edgeWidth)
    d:send("noiseScale", D.noiseScale)
    d:send("redMin", p.redMin)
    d:send("redMax", p.redMax)
    d:send("baseRed", p.baseRed)
    dissolve = d
  else
    -- Without it, appearing/vanishing things just fade.
    print("[shaders] dissolve unavailable: " .. tostring(d))
  end

  local okS, s = pcall(love.graphics.newShader, SHIELD_SRC)
  if okS then
    local S = Config.BOSS.shield
    s:send("hexScale", S.hexScale)
    s:send("look", { S.rimAlpha, S.hexAlpha, S.fillAlpha })
    shield = s
  else
    -- Without it the shield is a plain translucent circle.
    print("[shaders] shield unavailable: " .. tostring(s))
  end

  local ok, shader = pcall(love.graphics.newShader, RECOLOR_SRC)
  if not ok then
    -- Without the shader, player art simply keeps Kenney's red.
    print("[shaders] recolor unavailable: " .. tostring(shader))
    return
  end
  local p = Config.ART.recolor
  shader:send("redMin", p.redMin)
  shader:send("redMax", p.redMax)
  shader:send("baseRed", p.baseRed)
  recolor = shader
end

-- Turns the dissolve on for the next draws (see DISSOLVE_SRC): `progress`
-- 0..1, glowing `edge` color, `sweep` = build along (downX, downY) instead
-- of noise, `target` = player color to palette-swap to (nil = none).
-- Returns false when the shader is unavailable: the caller then fades its
-- draw with alpha = progress instead. Pair with Shaders.reset().
function Shaders.dissolve(progress, edge, sweep, downX, downY, target)
  if not dissolve then return false end
  dissolve:send("progress", progress)
  edgeBuf[1], edgeBuf[2], edgeBuf[3] = edge[1], edge[2], edge[3]
  dissolve:send("edge", edgeBuf)
  dissolve:send("mode", sweep and 1 or 0)
  if sweep then
    downBuf[1], downBuf[2] = downX, downY
    dissolve:send("down", downBuf)
  end
  if target then
    targetBuf[1], targetBuf[2], targetBuf[3] = target[1], target[2], target[3]
    dissolve:send("target", targetBuf)
  end
  dissolve:send("recolor", target and 1 or 0)
  love.graphics.setShader(dissolve)
  return true
end

-- Turns the sheen on (see SHEEN_SRC) with the band at `pos` (0..1 along
-- the diagonal; a little beyond both ends is fully off the image). Returns
-- false without the shader (then the caller skips the glint). The CALLER
-- sets the additive blend; pair with Shaders.reset().
function Shaders.sheen(pos)
  if not sheen then return false end
  sheen:send("screenMode", 0)
  sheen:send("pos", pos)
  love.graphics.setShader(sheen)
  return true
end

-- Same glint in screen space, for texts (their glyph UVs are font-atlas
-- UVs): a diagonal band `widthPx` wide centered on screen point (x, y),
-- given in the CURRENT transform's coordinates. Same contract as
-- Shaders.sheen.
function Shaders.sheenAt(x, y, widthPx)
  if not sheen then return false end
  local sx, sy = love.graphics.transformPoint(x, y)
  local _, k = love.graphics.transformPoint(0, 1)
  local _, k0 = love.graphics.transformPoint(0, 0)
  sheen:send("screenMode", 1)
  sheen:send("center", sx + sy * 0.4)
  sheen:send("bandPx", widthPx * math.abs(k - k0))
  love.graphics.setShader(sheen)
  return true
end

-- The sprite-space direction of the world's "down" for a sprite drawn by
-- Assets.draw at `angle` (the draw rotates by angle - sprite.rot).
function Shaders.spriteDown(role, angle)
  local s = Assets.sprite(role)
  local r = angle - (s and s.rot or 0)
  return math.sin(r), math.cos(r)
end

-- Boss shield of radius `r` at (x, y), in `color` ({r, g, b}), faded by
-- `alpha`. `t` drives the hex drift; `hits` is 4 {x, y, age, strength}
-- tables (see SHIELD_SRC). Leaves no shader set.
function Shaders.drawShield(x, y, r, color, alpha, t, hits)
  local g = love.graphics
  if shield then
    tintBuf[1], tintBuf[2], tintBuf[3] = color[1], color[2], color[3]
    shield:send("tint", tintBuf)
    shield:send("time", t)
    shield:send("hits", hits[1], hits[2], hits[3], hits[4])
    g.setShader(shield)
    g.setColor(1, 1, 1, alpha)
    g.draw(Assets.white, x - r, y - r, 0, r * 2, r * 2)
    g.setShader()
  else
    local S = Config.BOSS.shield
    g.setColor(color[1], color[2], color[3], alpha * S.fillAlpha * 2)
    g.circle("fill", x, y, r)
    g.setColor(color[1], color[2], color[3], alpha * S.rimAlpha)
    g.setLineWidth(2)
    g.circle("line", x, y, r)
    g.setLineWidth(1)
  end
end

-- Turns the recolor shader on with `color` ({r, g, b[, a]}) as the target.
-- Pair with Shaders.reset(). The uniform is only re-sent when it changes.
function Shaders.recolor(color)
  if not recolor then return end
  if currentTarget[1] ~= color[1] or currentTarget[2] ~= color[2] or currentTarget[3] ~= color[3] then
    currentTarget[1], currentTarget[2], currentTarget[3] = color[1], color[2], color[3]
    recolor:send("target", currentTarget)
  end
  love.graphics.setShader(recolor)
end

function Shaders.reset()
  love.graphics.setShader()
end

return Shaders
