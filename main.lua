-- Ponto de entrada. Só orquestra: nenhuma regra de jogo mora aqui.

local Config = require("src.config")
local Screen = require("src.screen")
local State  = require("src.state")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Input  = require("src.input")
local Smoke  = require("src.smoke")

local Lobby  = require("src.states.lobby")

local MAX_DT = 1 / 30   -- clamp anti-espiral da morte em frames longos

-- Lê os argumentos de linha de comando (love . --smoke 15 --debug --windowed).
local function parseArgs(args)
  local i = 1
  while args and args[i] do
    local a = args[i]
    if a == "--smoke" then
      Config.SMOKE = true
      local secs = tonumber(args[i + 1])
      if secs then Config.SMOKE_TIME = secs; i = i + 1 else Config.SMOKE_TIME = 15 end
    elseif a == "--debug" then
      Config.DEBUG = true
    elseif a == "--windowed" then
      Config.WINDOWED = true
    end
    i = i + 1
  end
end

function love.load(args)
  parseArgs(args)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough")
  math.randomseed(os.time())

  -- Smoke test e --windowed rodam em janela para não sequestrar a tela.
  if Config.SMOKE or Config.WINDOWED then
    love.window.setFullscreen(false)
    love.window.setMode(1280, 720, { resizable = true, vsync = Config.SMOKE and 0 or 1 })
  end

  Screen.load()
  Save.load()
  Audio.load()
  Input.load()
  if Config.SMOKE then Smoke.reset() end
  State.push(Lobby)
end

function love.update(dt)
  if dt > MAX_DT then dt = MAX_DT end

  -- O piloto do smoke escreve no device sintético ANTES do poll, para que
  -- Input veja a borda de subida dos botões normalmente.
  if Config.SMOKE then Smoke.update(dt) end

  Input.update(dt)
  if Input.quitRequested then
    love.event.quit()
    return
  end

  State.update(dt)
end

function love.draw()
  Screen.beginDraw()
  State.draw()
  Screen.endDraw()
end

function love.resize(w, h)
  Screen.resize(w, h)
end

function love.keypressed(key, scancode, isrepeat)
  State.keypressed(key, scancode, isrepeat)
end

function love.gamepadpressed(joystick, button)
  State.gamepadpressed(joystick, button)
end

function love.joystickadded(joystick)
  Input.addJoystick(joystick)
  State.joystickadded(joystick)
end

function love.joystickremoved(joystick)
  Input.removeJoystick(joystick)
  State.joystickremoved(joystick)
end

-- Loga o erro em stdout sempre; no modo smoke sai com código 1 para o
-- script de validação detectar a falha.
local defaultErrorHandler = love.errorhandler
function love.errorhandler(msg)
  local trace = debug.traceback(tostring(msg), 2)
  print("=== ERRO DE RUNTIME ===")
  print(trace)
  io.stdout:flush()
  if Config.SMOKE then
    os.exit(1)
  end
  return defaultErrorHandler(msg)
end
