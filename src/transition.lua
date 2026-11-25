-- Screen transitions (Config.FX.transition): a diagonal wipe from the top
-- left to the bottom right that reveals the new screen under a still of the
-- old one, with a glowing front.
--
-- Visual only: the state switch itself stays instant (input and the smoke
-- test timeline never wait). Usage: call Transition.start() right before a
-- big State.switch / State.reset. The switches happen between frames
-- (update / input callbacks), when Screen.canvas still holds exactly the
-- last frame shown, which is what gets copied.

local Config = require("src.config")
local Screen = require("src.screen")
local Audio  = require("src.audio")

local Transition = {}

local TR = Config.FX.transition

-- `front` runs from just before the top-left corner to just past the
-- bottom-right one along p = 0.6 u + 0.4 v. Behind it (p < front) the old
-- screen is gone; right ahead of it a thin band in the edge color; just
-- behind it a faint glow of that color over the new screen.
local WIPE_SRC = [[
uniform float front;
uniform vec3 edge;
uniform float edgeWidth;
uniform float glow;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    float d = uv.x * 0.6 + uv.y * 0.4 - front;
    if (d < 0.0) {
        float g = (1.0 - smoothstep(0.0, glow, -d)) * 0.45;
        return vec4(edge, g);
    }
    vec4 t = Texel(tex, uv);
    float e = 1.0 - smoothstep(0.0, edgeWidth, d);
    return vec4(mix(t.rgb, edge, e), 1.0);
}
]]

local shader
local snapshot
local active = false
local t = 0
local edgeBuf = { 1, 1, 1 }

function Transition.load()
  local ok, s = pcall(love.graphics.newShader, WIPE_SRC)
  if ok then
    s:send("edgeWidth", TR.edgeWidth)
    s:send("glow", TR.glow)
    edgeBuf[1], edgeBuf[2], edgeBuf[3] = TR.edge[1], TR.edge[2], TR.edge[3]
    s:send("edge", edgeBuf)
    shader = s
  else
    -- Without it the old screen simply fades out.
    print("[transition] wipe unavailable: " .. tostring(s))
  end
end

-- Takes the still of the screen being left and starts the wipe.
function Transition.start()
  local src = Screen.canvas
  if not src then return end
  local g = love.graphics
  local w, h = src:getDimensions()
  if not snapshot or snapshot:getWidth() ~= w or snapshot:getHeight() ~= h then
    if snapshot then snapshot:release() end
    snapshot = g.newCanvas(w, h)
  end
  g.push("all")
  g.setCanvas(snapshot)
  g.clear(0, 0, 0, 1)
  g.origin()
  g.setShader()
  g.setBlendMode("replace", "premultiplied")
  g.setColor(1, 1, 1, 1)
  g.draw(src, 0, 0)
  g.pop()
  active, t = true, 0
  Audio.play("transition")
end

function Transition.isActive()
  return active
end

-- Real time (runs under the pause too).
function Transition.update(dt)
  if not active then return end
  t = t + dt
  if t >= TR.time then active = false end
end

-- Over the new screen, inside Screen.beginDraw/endDraw.
function Transition.draw()
  if not active then return end
  local src = Screen.canvas
  -- A resize mid-wipe changes the canvas size: just drop the wipe.
  if src:getWidth() ~= snapshot:getWidth() or src:getHeight() ~= snapshot:getHeight() then
    active = false
    return
  end
  local g = love.graphics
  local k = math.min(1, t / TR.time)
  k = k * k * (3 - 2 * k)                      -- ease in-out
  g.push("all")
  g.origin()
  g.setBlendMode("alpha")
  if shader then
    shader:send("front", -0.06 + (1.12 + TR.edgeWidth) * k)
    g.setShader(shader)
    g.setColor(1, 1, 1, 1)
  else
    g.setColor(1, 1, 1, 1 - k)
  end
  g.draw(snapshot, 0, 0)
  g.pop()
end

return Transition
