-- ETAPA 2: arena ainda é placeholder. Prova que o vínculo de devices chega
-- inteiro do lobby. O diagnóstico de eixos/botões mora em states/inputtest.lua
-- (F5). A arena de verdade entra nas etapas 3+.

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

  for i = 1, playerCount do
    local d = devices[i]
    local y = 90 + (i - 1) * 40
    love.graphics.setColor(i == 1 and C.p1 or C.p2)
    love.graphics.rectangle("fill", 40, y, 16, 16)
    love.graphics.setColor(C.text)
    love.graphics.print(string.format("P%d  %s", i, d and d:displayName() or "?"), 68, y + 2)
    if d and not d.connected then
      love.graphics.setColor(C.doorWarn)
      love.graphics.print("DESCONECTADO", 68, y + 18)
    end
  end

  love.graphics.setColor(C.textDim)
  love.graphics.printf("BACK VOLTA AO LOBBY   -   F5 TESTE DE INPUT   -   SELECT+START SAI",
    0, H - 22, W, "center")

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
