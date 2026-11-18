-- Palette-swap shader for player-owned art.
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

local recolor
local currentTarget = { -1, -1, -1 }

function Shaders.load()
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
