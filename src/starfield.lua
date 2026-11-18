-- Static starfield behind the arena and the menus.
--
-- Covers the whole 640x360 screen (the HUD strip hides its top in-game) and
-- builds itself on first draw. Positions come from a fixed seed, so the sky
-- is the same on every screen and every match.
-- Stars are drawn live (no extra canvas to rebuild on resize), grouped by
-- sprite so LÖVE's autobatching turns them into two draw calls. A fraction
-- of them twinkle.

local Config = require("src.config")
local Assets = require("src.assets")

local Starfield = {}

local S = Config.ART.stars
local stars = {}   -- { x, y, size, alpha, sprite, twinkle, phase }

local function build()
  local area = { x = 0, y = 0, w = Config.VIRTUAL_W, h = Config.VIRTUAL_H }
  local rng = love.math.newRandomGenerator(S.seed)
  for i = 1, S.count do
    local big = rng:random() < S.bigShare
    stars[i] = {
      x = area.x + rng:random() * area.w,
      y = area.y + rng:random() * area.h,
      size = big and (S.bigMin + rng:random() * (S.bigMax - S.bigMin))
                 or (S.tinyMin + rng:random() * (S.tinyMax - S.tinyMin)),
      alpha = S.alphaMin + rng:random() * (S.alphaMax - S.alphaMin),
      sprite = big and "starSmall" or "starTiny",
      twinkle = rng:random() < S.twinkleShare,
      phase = rng:random() * math.pi * 2,
      rot = rng:random() * math.pi * 2,
    }
  end
end

local function drawGroup(sprite, time)
  local c = S.color
  for i = 1, #stars do
    local s = stars[i]
    if s.sprite == sprite then
      local a = s.alpha
      if s.twinkle then a = a * (0.45 + 0.55 * (0.5 + 0.5 * math.sin(time * S.twinkleSpeed + s.phase))) end
      love.graphics.setColor(c[1], c[2], c[3], a)
      Assets.draw(sprite, s.x, s.y, s.rot, s.size)
    end
  end
end

function Starfield.draw()
  if #stars == 0 then build() end
  local time = love.timer.getTime()
  drawGroup("starTiny", time)
  drawGroup("starSmall", time)
  love.graphics.setColor(1, 1, 1, 1)
end

return Starfield
