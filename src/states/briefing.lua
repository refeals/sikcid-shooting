-- Briefing antes da partida: janela sobre a arena (já montada e congelada)
-- apresentando os power-ups (e o botão de dash). A partida só começa quando um dos jogadores
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
local COLS = 2             -- two columns: one would not fit the 360px screen
local COL_W = 290

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

-- Dash button per device kind (the smoke bots read as a pad).
local DASH_KEYS = { gamepad = "RB / LB / B", scripted = "RB / LB / B",
                    keyboard = "SHIFT", touch = "BOTÃO ACIMA DE MIRAR" }

-- "DASH: <keys of every player's device, no repeats> - ...", built once.
local function dashLine(world)
  local keys, seen = {}, {}
  for i = 1, world.playerCount do
    local d = world.players[i].device
    local k = d and DASH_KEYS[d.kind]
    if k and not seen[k] then
      seen[k] = true
      keys[#keys + 1] = k
    end
  end
  if #keys == 0 then keys[1] = DASH_KEYS.gamepad end
  return "DASH: " .. table.concat(keys, " OU ") .. "  -  ATRAVESSA INIMIGOS E TIROS"
end

function Briefing:enter(world)
  self.world = world
  self.timer = 0
  self.dashText = dashLine(world)
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
        -- The match starts: the ships beam in (they were placed hidden
        -- under the briefing). Not on BACK, which leaves for the lobby.
        for k = 1, world.playerCount do world.players[k]:arrive() end
        State.pop()
        return
      elseif d:pressed("back") and not d:isDown("start") then
        -- A partida ainda não começou: voltar é só desistir do menu.
        Audio.play("menu_cancel")
        require("src.transition").start()   -- wipe back to the lobby
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

  -- Window: tab + subtitle + the power-ups in columns + the stacking rule.
  local rows = math.ceil(#defs / COLS)
  local pw = COLS * COL_W + 20
  local ph = Config.ART.ui.tabH + 64 + rows * ROW_H   -- +12: the dash line
  local px = math.floor((W - pw) * 0.5)
  local py = math.floor(Config.HUD_H + (H - Config.HUD_H - ph) * 0.5) - 12
  local top = UI.window(px, py, pw, ph, "POWER-UPS")

  UI.text("body", "PASSE POR CIMA PARA PEGAR", px, top + 8, C.textDim, pw, "center")

  -- One cell per power-up, filled column by column: icon, name, description.
  local y0 = top + 24
  for i = 1, #defs do
    local d = defs[i]
    local col = math.floor((i - 1) / rows)
    local row = (i - 1) % rows
    local cx = px + 10 + col * COL_W
    local cy = y0 + row * ROW_H + ICON * 0.5
    Pickup.drawIcon(d, cx + 14, cy, ICON)
    UI.text("body", d.name, cx + 30, cy - 9, d.color)
    UI.text("body", d.desc or "", cx + 30, cy + 1, C.text)
  end
  local y = y0 + rows * ROW_H

  -- Stacking rule.
  UI.text("body", string.format("%s SÃO ARMAS: PEGAR UMA TROCA A OUTRA.   %s ACUMULAM.",
    WEAPON_LETTERS, STACK_LETTERS), px, y + 4, C.textDim, pw, "center")
  -- The dash, with the button of each player's device.
  UI.text("body", self.dashText, px, y + 16, C.text, pw, "center")

  -- Pulsing call to start.
  local ready = self.timer >= ACCEPT_DELAY
  local a = ready and (0.6 + 0.4 * math.sin(self.timer * 5)) or 0.3
  local touch = Input.usingTouch()
  UI.text("title", touch and "TOQUE PARA COMEÇAR" or "START COMEÇA A PARTIDA", 0, py + ph + 8,
    { C.textWarn[1], C.textWarn[2], C.textWarn[3], a }, W, "center")
  if not touch then
    UI.text("body", "BACK VOLTA PARA A SELEÇÃO", 0, py + ph + 30, C.textDim, W, "center")
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Briefing
