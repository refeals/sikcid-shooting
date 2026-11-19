-- Ponto de entrada. Só orquestra: nenhuma regra de jogo mora aqui.

local Config = require("src.config")
local Screen = require("src.screen")
local State  = require("src.state")
local Save   = require("src.save")
local Audio  = require("src.audio")
local Music  = require("src.music")
local Input  = require("src.input")
local Smoke  = require("src.smoke")
local Profiler = require("src.profiler")
local Assets  = require("src.assets")
local Shaders = require("src.shaders")
local Background = require("src.background")
local UI      = require("src.ui")

local Lobby     = require("src.states.lobby")
local InputTest = require("src.states.inputtest")

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
    elseif a == "--smoke2p" then
      Config.SMOKE_2P = true      -- o smoke vincula um segundo bot
    elseif a == "--smokegod" then
      Config.SMOKE_GOD = true     -- bots invencíveis: mede FPS sem game over
    elseif a == "--fakepad" then
      Config.SMOKE_PAD = true     -- bot 1 entra por um gamepad falso
    elseif a == "--wave" then
      Config.SMOKE_WAVE = tonumber(args[i + 1]) or 1   -- começa numa wave alta
      i = i + 1
    elseif a == "--inputtest" then
      Config.INPUT_TEST = true   -- abre a tela de diagnóstico em vez do lobby
    elseif a == "--mute" then
      Config.AUDIO.master = 0
    elseif a == "--shots" then
      Config.SMOKE_SHOTS = true  -- smoke saves screenshots of each screen
    elseif a == "--smokesound" then
      Config.SMOKE_SOUND = true  -- smoke com som (por padrão ele roda mudo)
    elseif a == "--media" then
      Config.MEDIA = true        -- renders the store/frontend art (tools/media.lua)
    end
    i = i + 1
  end
  -- O smoke continua chamando Audio.play (o caminho é exercitado), mas com
  -- volume zero para não tocar som durante testes automáticos.
  if Config.SMOKE and not Config.SMOKE_SOUND then Config.AUDIO.master = 0 end
end

function love.load(args)
  parseArgs(args)
  -- Art generator: tools/ is not packed into the .love, so this only works
  -- from the project folder (`love . --media`).
  if Config.MEDIA then
    local ok, Media = pcall(require, "tools.media")
    if not ok then
      print("[media] tools/media.lua unavailable (run from the project folder): " .. tostring(Media))
      love.event.quit(1)
      return
    end
    Media.run()
    love.event.quit(0)
    return
  end
  -- No global texture filter: each asset sets its own (smooth sprites and UI,
  -- nearest for the pixel fonts). See src/assets.lua.
  love.graphics.setLineStyle("rough")
  math.randomseed(os.time())

  -- Smoke test e --windowed rodam em janela para não sequestrar a tela.
  if Config.SMOKE or Config.WINDOWED then
    love.window.setFullscreen(false)
    love.window.setMode(1280, 720, { resizable = true, vsync = Config.SMOKE and 0 or 1 })
  end

  Screen.load()
  Assets.load()
  Shaders.load()
  Background.load()
  UI.load()
  love.graphics.setFont(Assets.font("body"))
  Save.load()
  Audio.load()
  Music.load()
  Input.load()
  if Config.SMOKE then Smoke.reset() end

  if Config.INPUT_TEST then
    State.push(InputTest, true)
  else
    State.push(Lobby)
  end
end

function love.update(dt)
  Profiler.beginFrame()   -- só mede com DEBUG ligado
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
  Music.update(dt)   -- fades andam em qualquer tela, inclusive na pausa
end

function love.draw()
  Screen.beginDraw()
  State.draw()
  Screen.endDraw()
  -- Fecha a medição antes do present (a espera do vsync não entra na conta).
  Profiler.endFrame()
end

function love.resize()
  -- Read the real size instead of trusting the event's arguments: leaving
  -- fullscreen (smoke / --windowed) can deliver a stale resize with the old
  -- desktop size after setMode, which would scale the canvas for the wrong
  -- window and show only its top-left corner.
  Screen.resize(love.graphics.getDimensions())
end

function love.keypressed(key, scancode, isrepeat)
  -- F5 abre/fecha a tela de teste de input por cima de qualquer estado.
  if key == "f5" then
    local cur = State.current()
    if cur == InputTest then
      if cur.standalone then State.switch(Lobby) else State.pop() end
    else
      State.push(InputTest, false)
    end
    return
  end
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
