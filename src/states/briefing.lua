-- Briefing antes da partida: janela sobre a arena (já montada e congelada)
-- apresentando os power-ups. A partida só começa quando um dos jogadores
-- aperta START de novo — assim a transição do lobby para o jogo não joga
-- ninguém direto no meio da ação.
--
-- A lista vem de Powerups.DEFS: power-up novo aparece aqui sozinho.

local Config   = require("src.config")
local Input    = require("src.input")
local State    = require("src.state")
local Audio    = require("src.audio")
local Music    = require("src.music")
local Powerups = require("src.systems.powerups")
local Pickup   = require("src.entities.pickup")
local UI       = require("src.ui")

local Briefing = {}

local ACCEPT_DELAY = 0.3   -- ignora o START que saiu do lobby
local ICON = 16
local ROW_H = 22

-- Letras das armas e dos acumuláveis, montadas uma vez a partir dos dados.
local function lettersWhere(pred)
  local out = {}
  for i = 1, #Powerups.DEFS do
    local d = Powerups.DEFS[i]
    if pred(d) then out[#out + 1] = d.letter end
  end
  return table.concat(out, " ")
end

local WEAPON_LETTERS = lettersWhere(function(d) return d.weapon end)
local STACK_LETTERS  = lettersWhere(function(d) return not d.weapon and not d.permanent end)

function Briefing:enter(world)
  self.world = world
  self.timer = 0
  if Config.SMOKE then require("src.smoke").note("state", "briefing") end
end

function Briefing:leave()
  -- A partida começa. (Se o briefing foi fechado voltando ao lobby, o lobby
  -- pede a música de menu logo em seguida.)
  Music.play("game")
  if Config.SMOKE then
    require("src.smoke").note("state", "game/" .. self.world.playerCount .. "p")
  end
end

function Briefing:update(dt)
  self.timer = self.timer + dt
  if self.timer < ACCEPT_DELAY then return end

  local world = self.world
  for i = 1, world.playerCount do
    local d = world.players[i].device
    if d and d.connected then
      if d:pressed("start") then
        Audio.play("menu_confirm")
        State.pop()
        return
      elseif d:pressed("back") and not d:isDown("start") then
        -- A partida ainda não começou: voltar é só desistir do menu.
        Audio.play("menu_cancel")
        State.reset(require("src.states.lobby"))
        return
      end
    end
  end
end

function Briefing:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS
  local defs = Powerups.DEFS

  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- Window: tab + subtitle + one row per power-up + the stacking rule.
  local pw = 440
  local ph = Config.ART.ui.tabH + 52 + #defs * ROW_H
  local px = math.floor((W - pw) * 0.5)
  local py = math.floor(Config.HUD_H + (H - Config.HUD_H - ph) * 0.5) - 12
  local top = UI.window(px, py, pw, ph, "POWER-UPS")

  UI.text("body", string.format("PASSE POR CIMA PARA PEGAR  -  DURAM %dS", Config.POWERUP.duration),
    px, top + 8, C.textDim, pw, "center")

  -- One row per power-up: icon, name, description.
  local y = top + 24
  for i = 1, #defs do
    local d = defs[i]
    local cy = y + ICON * 0.5
    Pickup.drawIcon(d, px + 30, cy, ICON)
    UI.text("body", d.name, px + 48, cy - 5, d.color)
    UI.text("body", d.desc or "", px + 184, cy - 5, C.text)
    y = y + ROW_H
  end

  -- Stacking rule.
  UI.text("body", string.format("%s SÃO ARMAS: PEGAR UMA TROCA A OUTRA.   %s ACUMULAM.",
    WEAPON_LETTERS, STACK_LETTERS), px, y + 4, C.textDim, pw, "center")

  -- Pulsing call to start.
  local ready = self.timer >= ACCEPT_DELAY
  local a = ready and (0.6 + 0.4 * math.sin(self.timer * 5)) or 0.3
  UI.text("title", "START COMEÇA A PARTIDA", 0, py + ph + 8,
    { C.textWarn[1], C.textWarn[2], C.textWarn[3], a }, W, "center")
  UI.text("body", "BACK VOLTA PARA A SELEÇÃO", 0, py + ph + 30, C.textDim, W, "center")

  love.graphics.setColor(1, 1, 1, 1)
end

return Briefing
