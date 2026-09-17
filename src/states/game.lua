-- ETAPA 2: arena ainda é placeholder. Serve para provar que o vínculo de
-- devices chega inteiro do lobby e que cada jogador lê SÓ o seu input.
-- A arena de verdade (jogador, tiro, inimigos) entra nas etapas 3+.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")

local Game = {}

local devices = {}
local playerCount = 0

function Game:enter(boundDevices, count)
  devices = boundDevices or {}
  playerCount = count or 0
  if Config.SMOKE then
    require("src.smoke").note("state", "game/" .. playerCount .. "p")
  end
end

function Game:update(dt) -- luacheck: ignore
  for i = 1, playerCount do
    local d = devices[i]
    -- BACK volta ao lobby (sem START junto, que é o combo de saída).
    if d and d.connected and d:pressed("back") and not d:isDown("start") then
      State.switch(require("src.states.lobby"))
      return
    end
  end
end

function Game:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  love.graphics.setColor(C.arenaBg)
  love.graphics.rectangle("fill", 0, Config.HUD_H, W, H - Config.HUD_H)
  love.graphics.setColor(C.hudBg)
  love.graphics.rectangle("fill", 0, 0, W, Config.HUD_H)
  love.graphics.setColor(C.hudLine)
  love.graphics.line(0, Config.HUD_H, W, Config.HUD_H)

  love.graphics.setColor(C.text)
  love.graphics.printf(string.format("ARENA -- ETAPA 2 -- %d JOGADOR(ES)", playerCount),
    0, 12, W, "center")

  -- Leitura ao vivo dos eixos: valida deadzone radial e mapeamento gamepad.
  for i = 1, playerCount do
    local d = devices[i]
    local y = 70 + (i - 1) * 90
    local color = i == 1 and C.p1 or C.p2
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", 30, y, 16, 16)
    love.graphics.setColor(C.text)
    love.graphics.print(string.format("P%d  %s", i, d and d:displayName() or "?"), 56, y)
    if d then
      local mx, my = d:moveVector()
      local ax, ay = d:aimVector()
      local dx, dy = d:dpadVector()
      love.graphics.setColor(C.textDim)
      love.graphics.print(string.format("move %.2f,%.2f   aim %.2f,%.2f   dpad %.0f,%.0f",
        mx, my, ax, ay, dx, dy), 56, y + 18)
      love.graphics.print(string.format("start %s  back %s  fire %s  %s",
        tostring(d:isDown("start")), tostring(d:isDown("back")),
        tostring(d:isDown("fire")),
        d.connected and "" or "[DESCONECTADO]"), 56, y + 34)

      -- Bolinha mostrando o vetor de movimento já com deadzone aplicada.
      love.graphics.setColor(color)
      love.graphics.circle("line", 500, y + 20, 26)
      love.graphics.circle("fill", 500 + mx * 26, y + 20 + my * 26, 4)
    end
  end

  love.graphics.setColor(C.textDim)
  love.graphics.printf("BACK VOLTA AO LOBBY   -   SELECT+START SAI", 0, H - 22, W, "center")

  local p = Input.exitProgress()
  if p > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W - 92, 14, 80 * p, 5)
    love.graphics.setColor(C.hudLine)
    love.graphics.rectangle("line", W - 92.5, 13.5, 81, 6)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Game
