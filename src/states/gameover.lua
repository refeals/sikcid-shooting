-- Tela de fim de partida: resultado, recordes e volta ao lobby.
--
-- Recebe um resumo já fechado pelo game (scores, combo máximo, wave
-- alcançada) e o retorno de Save.submitMatch dizendo quais recordes caíram.

local Config = require("src.config")
local State  = require("src.state")
local Input  = require("src.input")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Music  = require("src.music")
local UI     = require("src.ui")
local Assets = require("src.assets")
local Background = require("src.background")

local GameOver = {}

local ACCEPT_DELAY = 0.6   -- evita voltar ao lobby no mesmo toque que matou

function GameOver:enter(summary)
  self.summary = summary
  self.timer = 0
  self.blink = 0
  self.musicBack = false
  self.musicDelay = Config.MUSIC.gameOverDelay
  if summary.sinceJingle then
    -- The arena's game over sequence already faded the music out and played
    -- the jingle: just bring the music in, gameOverDelay after the jingle.
    self.musicDelay = math.max(0, self.musicDelay - summary.sinceJingle)
  else
    -- A música da partida some em fade; o efeito de game over toca no
    -- silêncio e a música de game over entra depois de Config.MUSIC.gameOverDelay.
    Music.stop()
    Audio.play("game_over")
  end
  if Config.SMOKE then
    require("src.smoke").note("state", "gameover")
    require("src.smoke").bump("gameovers")
  end
end

function GameOver:update(dt)
  self.timer = self.timer + dt
  self.blink = self.blink + dt
  if not self.musicBack and self.timer >= self.musicDelay then
    self.musicBack = true
    Music.play("gameover")
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

-- One result window per player.
local function drawPlayerColumn(s, i, x, y, w)
  local C = Config.COLORS
  local color = Config.PLAYER_COLORS[i]
  local top = UI.window(x, y, w, 74, string.format("JOGADOR %d", i), color)
  UI.digits("digits", string.format("%07d", s.scores[i] or 0), x, top + 6, C.text, w, "center")
  UI.text("body", string.format("COMBO MÁX  %d", s.combos[i] or 0), x, top + 32, C.textDim, w, "center")
end

function GameOver:draw()
  local W = Config.VIRTUAL_W
  local C = Config.COLORS
  local s = self.summary

  Background.draw()   -- keeps the palette of the wave the match ended on

  UI.text("big", "FIM DE JOGO", 0, 22, C.doorWarn, W, "center")
  -- Two numbers on one centered line, in the digits font (box "0" otherwise).
  local reached, cleared = tostring(s.wave), tostring(s.wavesCleared)
  local w1 = UI.textNumberWidth("body", "digitsSmall", "WAVE ALCANÇADA: ", reached, "   -   ")
  local w2 = UI.textNumberWidth("body", "digitsSmall", "WAVES COMPLETAS: ", cleared)
  local lx = (W - w1 - w2) * 0.5
  UI.textNumber("body", "digitsSmall", "WAVE ALCANÇADA: ", reached, "   -   ", lx, 54, C.textDim)
  UI.textNumber("body", "digitsSmall", "WAVES COMPLETAS: ", cleared, nil, lx + w1, 54, C.textDim)

  if s.playerCount >= 2 then
    drawPlayerColumn(s, 1, W * 0.5 - 212, 74, 200)
    drawPlayerColumn(s, 2, W * 0.5 + 12, 74, 200)
    -- Label in the title font, the number in the digits font (Rocket Square
    -- draws "0" as a box), centered together.
    local label = "TOTAL DA DUPLA  "
    local total = tostring((s.scores[1] or 0) + (s.scores[2] or 0))
    local lw = Assets.font("title"):getWidth(label)
    local x0 = math.floor((W - lw - UI.digitsWidth("digits", total)) * 0.5)
    UI.text("title", label, x0, 154, C.text)
    UI.digits("digits", total, x0 + lw, 154 + Assets.font("title"):getAscent() - Assets.font("digits"):getAscent(),
      C.text)
  else
    drawPlayerColumn(s, 1, W * 0.5 - 100, 74, 200)
  end

  -- Records, with the ones just beaten blinking.
  local beat = s.beat
  local rw = 424
  local rx = W * 0.5 - rw * 0.5
  local top = UI.window(rx, 178, rw, 76, "RECORDES", C.textWarn)
  local labels = {
    { key = "solo", text = "MELHOR SOLO",     value = Save.get("solo") },
    { key = "duo",  text = "MELHOR EM DUPLA", value = Save.get("duo") },
    { key = "coop", text = "SOMA DA DUPLA",   value = Save.get("coop") },
  }
  local cw = rw / 3
  for i = 1, #labels do
    local L = labels[i]
    local x = rx + (i - 1) * cw
    local isNew = beat[L.key]
    local on = isNew and math.floor(self.blink * 6) % 2 == 0
    UI.text("body", L.text, x, top + 8, C.textDim, cw, "center")
    UI.digits("digits", tostring(L.value), x, top + 14, on and C.textWarn or (isNew and C.text or C.textDim),
      cw, "center")
    if isNew then
      UI.text("body", "NOVO RECORDE!", x, top + 40, on and C.textWarn or C.text, cw, "center")
    end
  end

  local touch = Input.usingTouch()
  UI.text("title", touch and "TOQUE PARA VOLTAR AO LOBBY" or "START VOLTA AO LOBBY", 0, 270,
    self.timer >= ACCEPT_DELAY and C.text or C.textDim, W, "center")
  -- The browser build has no quit (see Input), nor does a touch screen.
  if not Config.WEB and not touch then
    UI.text("body", "SEGURE SELECT PARA SAIR DO JOGO", 0, 294, C.textDim, W, "center")
    UI.exitBar(W * 0.5, 312)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return GameOver
