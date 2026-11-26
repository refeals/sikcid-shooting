-- Piloto automático do modo --smoke: injeta input sintético para exercitar
-- lobby, arena, waves e game over sem gamepad físico, e sai com código 0/1.
-- Usado na validação de cada etapa: `love . --smoke 15 ; echo $?`

local Config = require("src.config")
local Input  = require("src.input")

local Smoke = {
  t = 0,
  fpsMin = 9999,
  fpsTime = 0,         -- current 1s FPS window (see Smoke.update)
  fpsFrames = 0,
  stats = {},          -- preenchido pelo jogo via Smoke.note/Smoke.bump
  nextEvent = 1,
}

-- Gamepad falso, criado em Smoke.reset quando --fakepad está ligado.
local pad = nil

-- Timeline: {tempo, device, ação, valor} para botões, ou {tempo, 0, "fn", fn}.
-- Um pulso de botão = press + release. O device 2 só existe com --smoke2p.
local EVENTS = {
  -- Regressão: o LÖVE reanuncia os controles já ligados no boot. Adicionar o
  -- MESMO joystick de novo não pode criar um segundo device (senão o mesmo
  -- controle vira P1 e P2 no lobby).
  { 0.20, 0, "fn", function()
      if pad then love.joystickadded(pad.j); love.joystickadded(pad.j) end
    end },
  { 0.40, 1, "start", true  },   -- vincula o Jogador 1
  { 0.50, 1, "start", false },
  -- Seletor de cor: o P1 avança uma cor (depois do debounce do vínculo)...
  { 0.68, 1, "right", true  },
  { 0.72, 1, "right", false },
  { 0.80, 2, "fire",  true  },   -- qualquer botão do device 2 vincula o Jogador 2
  { 0.90, 2, "fire",  false },
  -- ...o P2 recua (passando pela cor do P1, que tem que ser pulada) e o P1
  -- sorteia. O lobby falha o smoke se as duas cores terminarem iguais.
  { 1.07, 2, "left",  true  },
  { 1.10, 2, "left",  false },
  { 1.12, 1, "random", true  },
  { 1.15, 1, "random", false },
  { 1.20, 1, "start", true  },   -- sai do lobby (debounce já passou)
  { 1.30, 1, "start", false },
  -- Abre e fecha a tela de teste de input (F5) por cima do briefing,
  -- exercitando push/pop da pilha com três estados empilhados.
  { 1.40, 0, "fn", function() love.keypressed("f5", "f5", false) end },
  { 1.55, 0, "fn", function() love.keypressed("f5", "f5", false) end },
  { 1.70, 1, "start", true  },   -- fecha o briefing: a partida começa
  { 1.80, 1, "start", false },
  -- Pausa e retoma (START no jogo).
  { 4.00, 1, "start", true  },
  { 4.10, 1, "start", false },
  { 4.60, 1, "start", true  },
  { 4.70, 1, "start", false },
  -- Queda e volta do controle (só com --fakepad): deve abrir a tela
  -- "AGUARDANDO CONTROLE" e retomar sozinho na reconexão.
  { 6.00, 0, "fn", function()
      if pad then love.joystickremoved(pad.j) end
    end },
  { 7.50, 0, "fn", function()
      if pad then love.joystickadded(pad.j) end
    end },
  -- BACK durante o jogo abre a pausa; BACK de novo pede confirmação de
  -- abandono; START cancela a confirmação; START retoma a partida.
  { 8.00, 1, "back",  true  },
  { 8.10, 1, "back",  false },
  { 8.50, 1, "back",  true  },
  { 8.60, 1, "back",  false },
  { 9.00, 1, "start", true  },
  { 9.10, 1, "start", false },
  { 9.50, 1, "start", true  },
  { 9.60, 1, "start", false },
}

-- With --shots: screenshots at these script times, chosen to land on each
-- screen of the timeline (lobby with both slots, briefing, arena, pause,
-- arena again). Files go to the LÖVE save directory (path printed at the end).
local SHOT_TIMES = { 1.00, 1.62, 3.50, 4.35, 7.00, 12.00 }

-- O consumo do roteiro é sequencial, então a lista tem que estar em ordem de
-- tempo (evita que um evento novo fora de lugar engula os seguintes).
table.sort(EVENTS, function(a, b) return a[1] < b[1] end)

-- ---------------------------------------------------------------------------
-- Gamepad falso (--fakepad): implementa a Gamepad API do LÖVE com um stub,
-- para exercitar o MESMO caminho de código dos controles de verdade (eixos
-- nomeados, deadzone radial, d-pad, isGamepadDown) em máquinas sem joystick
-- — o caso do WSL, onde o SDL não enxerga nenhum controle.
-- ---------------------------------------------------------------------------
local function makeFakePad()
  local st = {
    axes = { leftx = 0, lefty = 0, rightx = 0, righty = 0, triggerleft = 0, triggerright = 0 },
    buttons = {},
  }
  local j = {}
  function j:isGamepad() return true end
  function j:getGamepadAxis(a) return st.axes[a] or 0 end
  function j:isGamepadDown(...)
    for i = 1, select("#", ...) do
      if st.buttons[select(i, ...)] then return true end
    end
    return false
  end
  function j:getGUID() return "fakepad00000000000000000000000f" end
  function j:getName() return "FAKE PAD (SMOKE)" end
  function j:getID() return 99 end
  function j:getAxisCount() return 6 end
  function j:getButtonCount() return 15 end
  return { j = j, st = st }
end

-- Roteia os comandos do roteiro: device 1 vira o pad falso quando --fakepad
-- está ligado; o resto continua no device sintético.
-- Logical action -> fake gamepad button (anything else keeps its own name).
local PAD_BUTTONS = { fire = "a", left = "dpleft", right = "dpright", random = "y",
                      dash = "rightshoulder" }

-- --smoketouch: bot 1 is a finger. A button press taps the on-screen button
-- for that action (pause, color arrows, ABANDONAR) or, for START with no
-- button, the middle of the screen; actions with no touch form are skipped.
-- The move stick is one more finger held in the arena (no aim finger: the
-- bots leave aiming and firing to the auto-aim).
local Touch = require("src.touch")
local TAP, MOVE = "smk-tap", "smk-move"
local MOVE_X, MOVE_Y = 110, 280
local moveHeld = false

local function touchPress(action, value)
  if not value then
    Input.touchReleased(TAP)
    return
  end
  local x, y = Touch.buttonCenter(action)
  if not x and action == "start" and not Touch.sticksLive() then
    x, y = Config.VIRTUAL_W * 0.5, Config.VIRTUAL_H * 0.5
  end
  if x then Input.touchPressed(TAP, x, y) end
end

local function touchAxis(mx, my)
  local r = Config.TOUCH.stickRadius * 0.9
  if not Touch.sticksLive() then
    if moveHeld then Input.touchReleased(MOVE); moveHeld = false end
    return
  end
  if not moveHeld then Input.touchPressed(MOVE, MOVE_X, MOVE_Y); moveHeld = true end
  Input.touchMoved(MOVE, MOVE_X + mx * r, MOVE_Y + my * r)
end

local function press(which, action, value)
  if which == 1 and Config.SMOKE_TOUCH then
    touchPress(action, value)
  elseif which == 1 and pad then
    pad.st.buttons[PAD_BUTTONS[action] or action] = value or nil
  else
    Input.scriptPress(which, action, value)
  end
end

-- Move stick only: the aim stick stays centered, so the auto-aim picks the
-- targets and fires on its own (like a player who only steers).
local function axis(which, mx, my)
  if which == 1 and Config.SMOKE_TOUCH then
    touchAxis(mx, my)
  elseif which == 1 and pad then
    pad.st.axes.leftx, pad.st.axes.lefty = mx, my
    pad.st.axes.rightx, pad.st.axes.righty = 0, 0
  else
    Input.scriptAxis(which, mx, my, 0, 0)
  end
end

-- Bot dash trigger (see Smoke.update): an enemy within DASH_ENEMY px or an
-- enemy shot within DASH_SHOT px of the ship.
local DASH_ENEMY, DASH_SHOT = 40, 30
local dashHeld = { false, false }

-- Upgrade screen: each bot presses "right" 0..2 times, then START (or, on
-- the touch bot, taps a random card); one press or release per frame.
local upPlan = {
  { active = false, rights = 0, done = false, held = nil },
  { active = false, rights = 0, done = false, held = nil },
}

local function threatened(world, p)
  if world:nearestEnemy(p.x, p.y, DASH_ENEMY) then return true end
  local bullets = world.bullets
  local r2 = DASH_SHOT * DASH_SHOT
  for i = 1, bullets.count do
    local b = bullets.items[i]
    if b.owner == "enemy" and not b.dead then
      local dx, dy = b.x - p.x, b.y - p.y
      if dx * dx + dy * dy <= r2 then return true end
    end
  end
  return false
end

function Smoke.reset()
  Smoke.t = 0
  Smoke.fpsMin = 9999
  Smoke.fpsTime, Smoke.fpsFrames = 0, 0
  Smoke.nextEvent = 1
  Smoke.stats = {}
  Smoke.goTimer, Smoke.goPressed, Smoke.goReleased, Smoke.goReleaseAt = 0, false, false, 0
  Smoke.nextShot = 1
  dashHeld[1], dashHeld[2] = false, false
  upPlan[1].active, upPlan[2].active = false, false
  Smoke.upT = 0
  pad = nil
  if Config.SMOKE_PAD then
    pad = makeFakePad()
    Input.addJoystick(pad.j)
    Smoke.note("pad", "fake")
  end
  Smoke.pad = pad   -- exposto para testes pontuais de input
end

function Smoke.note(key, value)
  Smoke.stats[key] = value
end

function Smoke.bump(key, amount)
  Smoke.stats[key] = (Smoke.stats[key] or 0) + (amount or 1)
end

function Smoke.max(key, value)
  if (Smoke.stats[key] or -math.huge) < value then Smoke.stats[key] = value end
end

local function finish(code)
  local s = Smoke.stats
  s.devices = Input.count
  print(string.format(
    "[smoke] t=%.1fs estado=%s devices=%d fpsMin=%d waves=%d bosses=%d kills=%d deaths=%d gameovers=%d pickups=%d " ..
    "dashes=%d charges=%d splits=%d snipes=%d launches=%d upgrades=%d blades=%d bounces=%d shocks=%d recharges=%d subbosses=%d combo=%d pausas=%d esperas=%d peakEnemies=%d " ..
    "peakBullets=%d peakParticles=%d denied=%d deniedFx=%d cores=%s",
    Smoke.t, tostring(s.state or "?"), s.devices or 0, Smoke.fpsMin,
    s.waves or 0, s.bosses or 0, s.kills or 0, s.deaths or 0, s.gameovers or 0, s.pickups or 0, s.dashes or 0,
    s.charges or 0, s.splits or 0, s.snipes or 0, s.launches or 0, s.upgrades or 0,
    s.blades or 0, s.bounces or 0, s.shocks or 0, s.recharges or 0, s.subbosses or 0,
    s.combo or 0, s.pauses or 0, s.waits or 0, s.peakEnemies or 0, s.peakBullets or 0, s.peakParticles or 0,
    s.denied or 0, s.deniedFx or 0, tostring(s.colors or "?")))
  -- Both players ending on the same color means the picker's skip rule broke.
  if (s.colorClash or 0) > 0 then
    print("[smoke] FALHA: os dois jogadores terminaram com a mesma cor")
    code = 1
  end
  if Config.SMOKE_SHOTS then
    print("[smoke] screenshots in " .. love.filesystem.getSaveDirectory())
  end
  io.stdout:flush()
  love.event.quit(code or 0)
end

function Smoke.update(dt)
  Smoke.t = Smoke.t + dt

  -- FPS por janela de 1s, contado aqui e só depois do primeiro segundo. O
  -- love.timer.getFPS não serve: a primeira janela dele começa antes do
  -- love.load e inclui o tempo de carga, o que derrubava o fpsMin conforme o
  -- boot demorava mais ou menos (sem nada mudar no jogo).
  if Smoke.t > 1.0 then
    Smoke.fpsTime = Smoke.fpsTime + dt
    Smoke.fpsFrames = Smoke.fpsFrames + 1
    if Smoke.fpsTime >= 1.0 then
      local fps = math.floor(Smoke.fpsFrames / Smoke.fpsTime)
      if fps < Smoke.fpsMin then Smoke.fpsMin = fps end
      Smoke.fpsTime, Smoke.fpsFrames = 0, 0
    end
  end

  while EVENTS[Smoke.nextEvent] and Smoke.t >= EVENTS[Smoke.nextEvent][1] do
    local e = EVENTS[Smoke.nextEvent]
    if e[3] == "fn" then e[4]() else press(e[2], e[3], e[4]) end
    Smoke.nextEvent = Smoke.nextEvent + 1
  end

  local shotAt = SHOT_TIMES[Smoke.nextShot]
  if Config.SMOKE_SHOTS and shotAt and Smoke.t >= shotAt then
    love.graphics.captureScreenshot(string.format("smoke_%05.2f.png", shotAt))
    Smoke.nextShot = Smoke.nextShot + 1
  end

  -- Movement in circles of different periods: covers every direction and
  -- wall collisions. No aiming: the auto-aim targets and fires by itself.
  local t = Smoke.t
  axis(1, math.cos(t * 1.7), math.sin(t * 1.3))
  -- O segundo bot anda em contrafase, para os dois não ficarem colados.
  axis(2, math.cos(t * 1.1 + 2.2), math.sin(t * 1.9 + 1.0))

  -- No game over, aperta START uma vez para exercitar a volta ao lobby.
  local State = require("src.state")
  -- Before that, START once the arena's GAME OVER accepts it.
  local Game = require("src.states.game")

  -- Dash when threatened: an enemy or an enemy shot close by and the dash
  -- ready. Pressed for one frame (released on the next).
  for which = 1, 2 do
    if dashHeld[which] then
      press(which, "dash", false)
      dashHeld[which] = false
    elseif State.current() == Game and not Game.isEnding() then
      local p = Game.world.players[which]
      if p and p.alive and p.dashCd <= 0 and threatened(Game.world, p) then
        press(which, "dash", true)
        dashHeld[which] = true
        -- --shots: the first dash mid-burst (afterimages) and recharging (ring).
        if Config.SMOKE_SHOTS and not Smoke.dashShots then
          Smoke.dashShots = { Smoke.t + 0.08, Smoke.t + 0.6 }
        end
      end
    end
  end

  -- Upgrade screen: after 0.5s each bot moves its cursor and confirms.
  local Upgrade = require("src.states.upgrade")
  if State.current() == Upgrade then
    Smoke.upT = (Smoke.upT or 0) + dt
    if Config.SMOKE_SHOTS and not Smoke.upgradeShot and Smoke.upT > 0.45 then
      love.graphics.captureScreenshot("smoke_upgrade.png")
      Smoke.upgradeShot = true
    end
    local count = Game.world.playerCount
    for which = 1, count do
      local plan = upPlan[which]
      if not plan.active then
        plan.active, plan.rights, plan.done, plan.held = true, math.random(0, 2), false, nil
      end
      if Smoke.upT > 0.5 then
        if plan.held then
          press(which, plan.held, false)
          plan.held = nil
        elseif which == 1 and Config.SMOKE_TOUCH and not plan.done then
          plan.held = "card1" .. math.random(1, 3)
          press(which, plan.held, true)
          plan.done = true
        elseif plan.rights > 0 then
          plan.held, plan.rights = "right", plan.rights - 1
          press(which, "right", true)
        elseif not plan.done then
          plan.held, plan.done = "start", true
          press(which, "start", true)
        end
      end
    end
  else
    Smoke.upT = 0
    for which = 1, 2 do
      local plan = upPlan[which]
      if plan.held then press(which, plan.held, false); plan.held = nil end
      plan.active = false
    end
  end
  -- --shots: the first debut banner, kamikaze aim line and divisor split.
  if Config.SMOKE_SHOTS and State.current() == Game then
    local Spawner = require("src.systems.spawner")
    if not Smoke.debutShot and Spawner.introLabel and Spawner.banner > 0
      and Spawner.banner < Config.WAVE.bannerTime - 0.4 then
      love.graphics.captureScreenshot("smoke_debut.png")
      Smoke.debutShot = true
    end
    -- Sub-boss: its alert, then the fight a couple of seconds in.
    if not Smoke.subAlertShot and Spawner.subAlert > 0 and Spawner.subAlert < 0.8 then
      love.graphics.captureScreenshot("smoke_subboss.png")
      Smoke.subAlertShot = true
    end
    if Spawner.subboss and not Spawner.subboss.dead then
      Smoke.subT = (Smoke.subT or 0) + dt
      if not Smoke.subFightShot and Smoke.subT > 2.5 then
        love.graphics.captureScreenshot("smoke_subboss2.png")
        Smoke.subFightShot = true
      end
    end
    -- A power-up on the floor, and one blinking (its last seconds).
    local pk = Game.world.pickups
    for i = 1, pk.count do
      local p = pk.items[i]
      if not Smoke.pickupShot and p.age > 0.6 and p.life > 3 then
        love.graphics.captureScreenshot("smoke_pickup.png")
        Smoke.pickupShot = true
      elseif not Smoke.pickupBlinkShot and p:blinkOn() then
        love.graphics.captureScreenshot("smoke_pickupblink.png")
        Smoke.pickupBlinkShot = true
      end
    end
    local en = Game.world.enemies
    for i = 1, en.count do
      local e = en.items[i]
      if not Smoke.aimShot and e.type == "kamikaze" and e.state == "aim" and e.stateT < 0.25 then
        love.graphics.captureScreenshot("smoke_aim.png")
        Smoke.aimShot = true
      end
      if not Smoke.sniperShot and e.type == "sniper" and e.state == "aim" and e.stateT < 0.3 then
        love.graphics.captureScreenshot("smoke_sniper.png")
        Smoke.sniperShot = true
      end
      if not Smoke.carrierShot and e.type == "scout" and e.harmless > 0 and e.harmless < 0.15 then
        love.graphics.captureScreenshot("smoke_carrier.png")
        Smoke.carrierShot = true
      end
      if not Smoke.splitShot and e.type == "fragment" and e.harmless > 0 and e.harmless < 0.2 then
        love.graphics.captureScreenshot("smoke_split.png")
        Smoke.splitShot = true
      end
    end
  end
  local ds = Smoke.dashShots
  if ds and ds[1] and Smoke.t >= ds[1] then
    love.graphics.captureScreenshot(ds[2] and "smoke_dash.png" or "smoke_dashring.png")
    table.remove(ds, 1)
  end
  if State.current() == Game and Game.isEnding() then
    -- The screenshot is saved at the end of the frame: take it one frame
    -- before START switches the screen.
    if Game.endAccepting() and Config.SMOKE_SHOTS and not Smoke.endShot then
      love.graphics.captureScreenshot("smoke_gameover.png")
      Smoke.endShot = true
    elseif Game.endAccepting() and not Smoke.endPressed then
      press(1, "start", true)
      Smoke.endPressed = true
      Smoke.bump("endings")
    end
  elseif Smoke.endPressed and not Smoke.endReleased then
    press(1, "start", false)
    Smoke.endReleased = true
  end
  -- Results screen: START once to go back to the lobby. The release is timed
  -- from the press, not tied to the screen: START switches to the lobby in
  -- the same frame, and a release that waited for the results screen would
  -- never come (START would stay held in the lobby).
  if State.current() == require("src.states.gameover") then
    Smoke.goTimer = (Smoke.goTimer or 0) + dt
    if not Smoke.goPressed and Smoke.goTimer > 1.2 then
      press(1, "start", true)
      Smoke.goPressed = true
      Smoke.goReleaseAt = Smoke.t + 0.1
    end
  end
  if Smoke.goPressed and not Smoke.goReleased and Smoke.t >= Smoke.goReleaseAt then
    press(1, "start", false)
    Smoke.goReleased = true
  end

  if Smoke.t >= (Config.SMOKE_TIME or 15) then
    finish(0)
  end
end

return Smoke
