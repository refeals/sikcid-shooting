-- Tela de fim de partida: resultado, recordes e volta ao lobby.
--
-- Recebe um resumo já fechado pelo game (scores, combo máximo, wave
-- alcançada) e o retorno de Save.submitMatch dizendo quais recordes caíram.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Music  = require("src.music")

local GameOver = {}

local ACCEPT_DELAY = 0.6   -- evita voltar ao lobby no mesmo toque que matou

function GameOver:enter(summary)
  self.summary = summary
  self.timer = 0
  self.blink = 0
  self.musicBack = false
  -- A música da partida some em fade; o efeito de game over toca no
  -- silêncio e a música de menu volta depois de Config.MUSIC.gameOverDelay.
  Music.stop()
  Audio.play("game_over")
  if Config.SMOKE then
    require("src.smoke").note("state", "gameover")
    require("src.smoke").bump("gameovers")
  end
end

function GameOver:update(dt)
  self.timer = self.timer + dt
  self.blink = self.blink + dt
  if not self.musicBack and self.timer >= Config.MUSIC.gameOverDelay then
    self.musicBack = true
    Music.play("menu")
  end
  if self.timer < ACCEPT_DELAY then return end

  local s = self.summary
  for i = 1, s.playerCount do
    local d = s.devices[i]
    if d and d.connected and d:pressed("start") and not d:isDown("back") then
      State.switch(require("src.states.lobby"))
      return
    end
  end
end

-- Uma coluna de resultado por jogador.
local function drawPlayerColumn(s, i, x, w)
  local C = Config.COLORS
  local color = i == 1 and C.p1 or C.p2

  love.graphics.setColor(color)
  love.graphics.printf(string.format("JOGADOR %d", i), x, 96, w, "center")
  love.graphics.setColor(C.text)
  love.graphics.printf(string.format("%07d", s.scores[i] or 0), x, 114, w, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf(string.format("COMBO MAX  %d", s.combos[i] or 0), x, 132, w, "center")
end

function GameOver:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS
  local s = self.summary

  love.graphics.setColor(C.arenaBg)
  love.graphics.rectangle("fill", 0, 0, W, H)

  love.graphics.setColor(C.doorWarn)
  love.graphics.printf("FIM DE JOGO", 0, 40, W, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf(string.format("WAVE ALCANCADA: %d   -   WAVES COMPLETAS: %d",
    s.wave, s.wavesCleared), 0, 60, W, "center")

  if s.playerCount >= 2 then
    drawPlayerColumn(s, 1, W * 0.5 - 220, 200)
    drawPlayerColumn(s, 2, W * 0.5 + 20, 200)
    love.graphics.setColor(C.text)
    love.graphics.printf(string.format("TOTAL DA DUPLA  %d", (s.scores[1] or 0) + (s.scores[2] or 0)),
      W * 0.5 - 150, 156, 300, "center")
  else
    drawPlayerColumn(s, 1, W * 0.5 - 150, 300)
  end

  -- Recordes, com destaque para o que acabou de cair.
  local beat = s.beat
  local y = 196
  love.graphics.setColor(C.textDim)
  love.graphics.printf("RECORDES", 0, y, W, "center")

  local labels = {
    { key = "solo", text = "SOLO",  value = Save.get("solo") },
    { key = "duo",  text = "DUPLA", value = Save.get("duo") },
    { key = "coop", text = "COOP",  value = Save.get("coop") },
  }
  for i = 1, #labels do
    local L = labels[i]
    local x = W * 0.5 - 300 + (i - 1) * 205
    if beat[L.key] then
      -- Pisca o recorde recém-batido.
      if math.floor(self.blink * 6) % 2 == 0 then
        love.graphics.setColor(C.textWarn)
      else
        love.graphics.setColor(C.text)
      end
      love.graphics.printf(string.format("%s %d", L.text, L.value), x, y + 18, 190, "center")
      love.graphics.printf("NOVO RECORDE!", x, y + 32, 190, "center")
    else
      love.graphics.setColor(C.textDim)
      love.graphics.printf(string.format("%s %d", L.text, L.value), x, y + 18, 190, "center")
    end
  end

  love.graphics.setColor(self.timer >= ACCEPT_DELAY and C.text or C.textDim)
  love.graphics.printf("START VOLTA AO LOBBY", 0, 288, W, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf("SEGURE SELECT PARA SAIR DO JOGO", 0, 304, W, "center")

  local ex = Input.exitProgress()
  if ex > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", W * 0.5 - 60, 324, 120 * ex, 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return GameOver
