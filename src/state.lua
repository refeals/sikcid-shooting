-- Máquina de estados de tela em pilha.
-- Pause é `push` (o estado de baixo continua sendo desenhado).

local State = {
  stack = {},
  count = 0,
}

local function call(s, name, ...)
  if s and s[name] then return s[name](s, ...) end
end

function State.current()
  return State.stack[State.count]
end

function State.push(state, ...)
  State.count = State.count + 1
  State.stack[State.count] = state
  call(state, "enter", ...)
  return state
end

function State.pop(...)
  local s = State.stack[State.count]
  if not s then return end
  call(s, "leave", ...)
  State.stack[State.count] = nil
  State.count = State.count - 1
  local below = State.stack[State.count]
  call(below, "resume", ...)
  return s
end

-- Troca o topo da pilha (usado entre lobby/game/gameover).
function State.switch(state, ...)
  local s = State.stack[State.count]
  if s then
    call(s, "leave")
    State.stack[State.count] = nil
    State.count = State.count - 1
  end
  return State.push(state, ...)
end

-- Limpa tudo e entra em `state` (volta ao lobby a partir de qualquer lugar).
function State.reset(state, ...)
  for i = State.count, 1, -1 do
    call(State.stack[i], "leave")
    State.stack[i] = nil
  end
  State.count = 0
  return State.push(state, ...)
end

function State.update(dt)
  call(State.current(), "update", dt)
end

-- Desenha a pilha inteira de baixo para cima (overlay de pause por cima).
function State.draw()
  for i = 1, State.count do
    call(State.stack[i], "draw", i < State.count)
  end
end

function State.keypressed(key, scancode, isrepeat)
  call(State.current(), "keypressed", key, scancode, isrepeat)
end

function State.focus(focused)
  call(State.current(), "focus", focused)
end

function State.gamepadpressed(joystick, button)
  call(State.current(), "gamepadpressed", joystick, button)
end

function State.joystickadded(joystick)
  for i = 1, State.count do call(State.stack[i], "joystickadded", joystick) end
end

function State.joystickremoved(joystick)
  for i = 1, State.count do call(State.stack[i], "joystickremoved", joystick) end
end

return State
