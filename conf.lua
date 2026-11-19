-- Configuração de janela e módulos do LÖVE.
-- Lido pelo LÖVE antes de main.lua, por isso não pode depender de src/.

function love.conf(t)
  -- love._os is set before love.conf runs; love.js reports "Web".
  local web = love._os == "Web"

  t.identity = "sikcid-shootin"        -- pasta de save (love.filesystem)
  t.version = "11.4"
  t.console = false

  t.window.title = "SikCid Shootin'"
  t.window.width = 1280               -- 640x360 * 2, janela de desenvolvimento
  t.window.height = 720
  t.window.resizable = true
  -- Browsers refuse fullscreen without a user gesture; the web page scales
  -- the canvas itself (web/index.html).
  t.window.fullscreen = not web
  t.window.fullscreentype = "desktop" -- borderless, sem trocar modo de vídeo
  t.window.vsync = 1
  t.window.minwidth = 640
  t.window.minheight = 360

  -- Módulos desligados economizam memória/boot em hardware modesto.
  t.modules.audio = true              -- ligado só para o futuro src/audio.lua
  t.modules.sound = true
  t.modules.joystick = true
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
  t.modules.thread = false
end
