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
local white             -- 1x1 white image the shield shader is drawn on
local currentTarget = { -1, -1, -1 }
local tintBuf = { 1, 1, 1 }

function Shaders.load()
  local data = love.image.newImageData(1, 1)
  data:setPixel(0, 0, 1, 1, 1, 1)
  white = love.graphics.newImage(data)

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
    g.draw(white, x - r, y - r, 0, r * 2, r * 2)
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
