-- Tela de diagnóstico de input (não faz parte do fluxo do jogo).
--
-- Mostra TODOS os devices conhecidos com leitura ao vivo de eixos, d-pad,
-- botões e combo de saída. Serve para conferir o mapeamento SDL no Batocera
-- sem precisar entrar na partida.
--
-- Como abrir:
--   love . --inputtest     (entra direto, em vez do menu)
--   F5                     (abre/fecha por cima de qualquer tela)
--   OPÇÕES > TESTAR CONTROLES (the way in on Batocera, which has no keyboard)
--
-- BACK (any device, or VOLTAR on the touch screen) closes it: back to the
-- screen below, or to the main menu when opened standalone. Down scrolls the
-- list when there are more devices than fit.

local Config = require("src.config")
local Input  = require("src.input")
local State  = require("src.state")
local UI     = require("src.ui")
local Nav    = require("src.nav")

local InputTest = {}

local ROW_H = 74
local MAX_ROWS = 4
local scroll = 0          -- primeira linha visível, quando há muitos devices

-- Desenha um "analógico": círculo de limite + ponto na posição do vetor.
local function drawStick(cx, cy, r, x, y, color, label)
  local C = Config.COLORS
  love.graphics.setColor(C.hudLine)
  love.graphics.circle("line", cx, cy, r)
  -- Círculo interno = deadzone (o ponto nunca cai dentro dele).
  love.graphics.setColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.5)
  love.graphics.circle("line", cx, cy, r * Config.DEADZONE)
  love.graphics.setColor(color)
  love.graphics.circle("fill", cx + x * r, cy + y * r, 3)
  love.graphics.setColor(C.textDim)
  love.graphics.printf(label, cx - 30, cy + r + 2, 60, "center")
end

local BTN_W = 44   -- fits "START" in the body font (Kenney Mini Square 8)

local function drawButton(x, y, label, active)
  local C = Config.COLORS
  love.graphics.setColor(active and C.textWarn or C.hudLine)
  love.graphics.rectangle(active and "fill" or "line", x + 0.5, y + 0.5, BTN_W, 13)
  love.graphics.setColor(active and C.hudBg or C.textDim)
  love.graphics.printf(label, x, y + 1, BTN_W + 1, "center")
  return x + BTN_W + 4
end

local function drawDevice(d, y)
  local C = Config.COLORS
  local W = Config.VIRTUAL_W

  love.graphics.setColor(C.hudBg)
  love.graphics.rectangle("fill", 6, y, W - 12, ROW_H - 6)
  love.graphics.setColor(d.connected and C.hudLine or C.doorWarn)
  love.graphics.rectangle("line", 6.5, y + 0.5, W - 13, ROW_H - 7)

  -- Cor do jogador se o device estiver vinculado.
  local color = Config.PLAYER_COLORS[d.boundTo] or C.text

  love.graphics.setColor(color)
  love.graphics.print(d:displayName(), 14, y + 6)
  love.graphics.setColor(C.textDim)
  love.graphics.print(string.format("[%s]%s%s",
    d.kind,
    d.connected and "" or "  DESCONECTADO",
    d.boundTo and ("  P" .. d.boundTo) or ""), 14, y + 22)

  local mx, my = d:moveVector()
  local ax, ay = d:aimVector()
  local dx, dy = d:dpadVector()
  love.graphics.setColor(C.textDim)
  love.graphics.print(string.format("move %+.2f %+.2f", mx, my), 14, y + 38)
  love.graphics.print(string.format("aim  %+.2f %+.2f", ax, ay), 14, y + 52)

  drawStick(210, y + 32, 22, mx, my, color, "ESQ")
  drawStick(272, y + 32, 22, ax, ay, color, "DIR")
  drawStick(334, y + 32, 22, dx, dy, color, "DPAD")

  local bx0 = 380
  local bx = drawButton(bx0, y + 10, "START", d:isDown("start"))
  bx = drawButton(bx, y + 10, "BACK", d:isDown("back"))
  drawButton(bx, y + 10, "FIRE", d:isDown("fire"))

  -- Progresso do combo de saída deste device.
  local barW = BTN_W * 3 + 8
  local p = d:exitProgress()
  love.graphics.setColor(C.textDim)
  love.graphics.print("SAIR", bx0, y + 34)
  love.graphics.setColor(C.hudLine)
  love.graphics.rectangle("line", bx0 + 34.5, y + 39.5, barW - 34, 7)
  if p > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.rectangle("fill", bx0 + 35, y + 40, (barW - 35) * p, 6)
  end
end

function InputTest:enter(standalone)
  -- standalone = entrou por --inputtest (não há tela por baixo para voltar).
  self.standalone = standalone or false
  scroll = 0
  if Config.SMOKE then require("src.smoke").bump("menus") end
end

-- Closes the screen (also F5, in main.lua).
function InputTest:close()
  if self.standalone then
    State.switch(require("src.states.menu"))
  else
    State.pop()
  end
end

function InputTest:update()
  local cmd = Nav.poll()
  if cmd == "back" then
    self:close()
  elseif cmd == "down" and Input.count > MAX_ROWS then
    -- Rola a lista quando há mais devices do que cabe na tela.
    scroll = (scroll + 1) % math.max(1, Input.count - MAX_ROWS + 1)
  end
end

function InputTest:draw()
  local W, H = Config.VIRTUAL_W, Config.VIRTUAL_H
  local C = Config.COLORS

  love.graphics.setColor(0, 0, 0, self.standalone and 1 or 0.85)
  love.graphics.rectangle("fill", 0, 0, W, H)

  UI.text("title", "TESTE DE INPUT", 0, 2, C.text, W, "center")
  love.graphics.setColor(C.textDim)
  love.graphics.printf(string.format("%d device(s)  -  %d joystick(s) no SDL  -  deadzone %.2f radial",
    Input.count, love.joystick.getJoystickCount(), Config.DEADZONE), 0, 22, W, "center")

  local y = 42
  local shown = 0
  for i = 1 + scroll, Input.count do
    if shown >= MAX_ROWS then break end
    drawDevice(Input.devices[i], y)
    y = y + ROW_H
    shown = shown + 1
  end

  if Input.count == 0 then
    love.graphics.setColor(C.textDim)
    love.graphics.printf("nenhum device", 0, 120, W, "center")
  end

  -- Joysticks que o SDL vê mas não sabe mapear: aparecem aqui para não
  -- ficar a impressão de que o jogo simplesmente ignorou o controle.
  if Input.unmappedCount > 0 then
    love.graphics.setColor(C.doorWarn)
    love.graphics.printf("SEM MAPEAMENTO DE GAMEPAD (SDL)", 0, y + 2, W, "center")
    love.graphics.setColor(C.textDim)
    for i = 1, Input.unmappedCount do
      local u = Input.unmapped[i]
      love.graphics.printf(string.format("%s  -  %d eixos, %d botões  -  guid %s",
        u.name, u.axes, u.buttons, u.guid:sub(1, 16)), 0, y + 16 + (i - 1) * 12, W, "center")
    end
  elseif love.joystick.getJoystickCount() == 0 then
    love.graphics.setColor(C.textDim)
    love.graphics.printf("nenhum joystick visível para o SDL", 0, y + 4, W, "center")
  end

  love.graphics.setColor(C.textDim)
  local hint = self.standalone and "BACK OU F5 VAI PARA O MENU" or "BACK OU F5 FECHA"
  -- The browser build has no quit (see Input).
  if not Config.WEB then hint = hint .. "   -   SEGURE ESC/SELECT PARA SAIR" end
  if Input.count > MAX_ROWS then hint = "BAIXO ROLA A LISTA   -   " .. hint end
  love.graphics.printf(hint, 0, H - 16, W, "center")
  Nav.drawTouchBack(H - 44)
  love.graphics.setColor(1, 1, 1, 1)
end

return InputTest
