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
local Post    = require("src.post")
local Transition = require("src.transition")
local Background = require("src.background")
local UI      = require("src.ui")
local Touch   = require("src.touch")
local Options = require("src.options")

local Menu      = require("src.states.menu")
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
    elseif a == "--upgrades" then
      Config.START_UPGRADES = tonumber(args[i + 1]) or 0   -- start with N random upgrades
      i = i + 1
    elseif a == "--inputtest" then
      Config.INPUT_TEST = true   -- opens the input test instead of the menu
    elseif a == "--mute" then
      Config.MUTE = true         -- both volumes at 0 this session (src/options.lua)
    elseif a == "--batocera" then
      Config.BATOCERA = true     -- the Batocera launcher: always fullscreen
    elseif a == "--shots" then
      Config.SMOKE_SHOTS = true  -- smoke saves screenshots of each screen
    elseif a == "--smokesound" then
      Config.SMOKE_SOUND = true  -- smoke com som (por padrão ele roda mudo)
    elseif a == "--touchmouse" then
      Config.TOUCH_MOUSE = true  -- the mouse acts as one finger (test touch on a PC)
    elseif a == "--smoketouch" then
      Config.SMOKE_TOUCH = true  -- smoke bot 1 plays through synthetic touches
    elseif a == "--fx" then
      -- Glow quality: high | low | off (see Config.FX); locks the OPÇÕES item.
      if args[i + 1] then Config.FX_FLAG = args[i + 1]; i = i + 1 end
    elseif a == "--lang" then
      -- Language this session: en | es | pt (src/i18n.lua); locks the OPÇÕES item.
      if args[i + 1] then Config.LANG_FLAG = args[i + 1]; i = i + 1 end
    elseif a == "--media" then
      Config.MEDIA = true        -- renders the store/frontend art (tools/media.lua)
    elseif a == "--powerup" then
      -- power-ups handed to everyone at each wave start (comma list of ids)
      Config.START_POWERUPS = {}
      for id in (args[i + 1] or ""):gmatch("[^,]+") do
        Config.START_POWERUPS[#Config.START_POWERUPS + 1] = id
      end
      i = i + 1
    elseif a == "--smokelog" then
      Config.SMOKE_LOG = true    -- smoke writes the run log too (runs-smoke.csv)
    elseif a == "--curve" then
      Config.CURVE = true        -- prints the wave curve table and quits (src/curve.lua)
    end
    i = i + 1
  end
  -- O smoke continua chamando Audio.play (o caminho é exercitado), mas com
  -- volume zero para não tocar som durante testes automáticos.
  if Config.SMOKE and not Config.SMOKE_SOUND then Config.MUTE = true end
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
  -- Wave curve table (tuning Config.WAVE / ENEMY_MIX / ELITE / BOSS).
  if Config.CURVE then
    require("src.curve").print()
    love.event.quit(0)
    return
  end
  -- No global texture filter: each asset sets its own (smooth sprites and UI,
  -- nearest for the pixel fonts). See src/assets.lua.
  love.graphics.setLineStyle("rough")
  math.randomseed(os.time())

  -- The saved options (and the flags over them). Before the modules: it sets
  -- the FX quality Post.load reads and the language.
  Options.load()

  -- Smoke: the three languages must have the same keys (src/i18n.lua).
  if Config.SMOKE then
    local errors = require("src.i18n").check()
    if #errors > 0 then
      for i = 1, #errors do print("[i18n] " .. errors[i]) end
      print(string.format("[smoke] FALHA: %d problema(s) nos idiomas (src/lang/)", #errors))
      love.event.quit(1)
      return
    end
  end

  -- Smoke test and --windowed run in a window so they don't take over the
  -- screen; so does a PC whose OPÇÕES turned fullscreen off (conf.lua can't
  -- read the save, so it opens fullscreen and switches here).
  if Options.startWindowed() then
    local win = Config.OPTIONS.window
    love.window.setFullscreen(false)
    love.window.setMode(win.w, win.h, { resizable = true, vsync = Config.SMOKE and 0 or 1,
      minwidth = Config.VIRTUAL_W, minheight = Config.VIRTUAL_H })
  end

  Screen.load()
  Assets.load()
  Shaders.load()
  Post.load()
  Transition.load()
  Background.load()
  UI.load()
  love.graphics.setFont(Assets.font("body"))
  Save.load()
  Audio.load()
  Music.load()
  Options.apply()   -- volumes, shake, distortion
  Input.load()
  if Config.SMOKE then Smoke.reset() end

  if Config.INPUT_TEST then
    State.push(InputTest, true)
  else
    State.push(Menu)
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

  -- Before the states: a wipe started by a switch this frame shows its
  -- first frame at t = 0.
  Transition.update(dt)
  State.update(dt)
  Music.update(dt)   -- fades andam em qualquer tela, inclusive na pausa
end

function love.draw()
  Screen.beginDraw()
  Touch.beginFrame()   -- the screens re-register their touch buttons as they draw
  State.draw()
  Transition.draw()    -- the still of the previous screen, wiping away
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
      cur:close()
    else
      State.push(InputTest, false)
    end
    return
  end
  State.keypressed(key, scancode, isrepeat)
end

-- Touch screen, in logical coordinates (see src/touch.lua). LÖVE gives touch
-- positions in window pixels, like the mouse.
function love.touchpressed(id, x, y)
  Input.touchPressed(id, Screen.toVirtual(x, y))
end

function love.touchmoved(id, x, y)
  Input.touchMoved(id, Screen.toVirtual(x, y))
end

function love.touchreleased(id)
  Input.touchReleased(id)
end

-- --touchmouse: the mouse plays one finger. Mouse events the system makes up
-- from real touches (istouch) are skipped: the touch callbacks got them.
function love.mousepressed(x, y, button, istouch)
  if Config.TOUCH_MOUSE and button == 1 and not istouch then
    Input.touchPressed("mouse", Screen.toVirtual(x, y))
  end
end

function love.mousemoved(x, y, _, _, istouch)
  if Config.TOUCH_MOUSE and not istouch and love.mouse.isDown(1) then
    Input.touchMoved("mouse", Screen.toVirtual(x, y))
  end
end

function love.mousereleased(_, _, button, istouch)
  if Config.TOUCH_MOUSE and button == 1 and not istouch then
    Input.touchReleased("mouse")
  end
end

-- Closing the game mid-match still closes its run log entry ("saiu") and
-- adds the match to the machine stats (RECORDES).
function love.quit()
  require("src.runlog").quit()
  -- Only if a match ever started (no need to load the arena to quit the menu).
  local Game = package.loaded["src.states.game"]
  if Game then Game.quit() end
  return false
end

function love.focus(focused)
  -- A finger lifted while the app was in the background never reports it.
  if not focused then Touch.releaseAll() end
  State.focus(focused)
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
