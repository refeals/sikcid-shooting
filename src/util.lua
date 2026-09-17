-- Helpers matemáticos e de tabela.
-- Nenhuma função aloca tabela: vetores entram e saem como valores soltos.

local Util = {}

local sqrt, floor, random = math.sqrt, math.floor, math.random

function Util.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function Util.lerp(a, b, t)
  return a + (b - a) * t
end

-- Move `a` na direção de `b` no máximo `step` (sem passar do alvo).
function Util.approach(a, b, step)
  if a < b then
    a = a + step
    if a > b then return b end
  else
    a = a - step
    if a < b then return b end
  end
  return a
end

function Util.sign(v)
  if v > 0 then return 1 elseif v < 0 then return -1 end
  return 0
end

-- Distância ao quadrado: usada em toda colisão (evita sqrt).
function Util.dist2(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return dx * dx + dy * dy
end

function Util.len2(x, y)
  return x * x + y * y
end

-- Normaliza; devolve 0,0,0 se o vetor for nulo. Retorna x, y, comprimento.
function Util.normalize(x, y)
  local l2 = x * x + y * y
  if l2 <= 0 then return 0, 0, 0 end
  local l = sqrt(l2)
  return x / l, y / l, l
end

function Util.randRange(a, b)
  return a + random() * (b - a)
end

function Util.randInt(a, b)
  return random(a, b)
end

-- Sorteio ponderado sobre uma lista de itens com campo `.weight`.
-- `n` é o tamanho útil da lista (permite reusar buffers).
function Util.weightedPick(list, n)
  n = n or #list
  local total = 0
  for i = 1, n do total = total + (list[i].weight or 0) end
  if total <= 0 then return nil end
  local roll = random() * total
  local acc = 0
  for i = 1, n do
    acc = acc + (list[i].weight or 0)
    if roll <= acc then return list[i] end
  end
  return list[n]
end

-- Remoção O(1) sem preservar ordem. Devolve o novo tamanho.
-- Uso: `count = Util.swapRemove(items, i, count)` e NÃO avançar o índice.
function Util.swapRemove(t, i, count)
  t[i] = t[count]
  t[count] = nil
  return count - 1
end

function Util.shuffle(t, n)
  n = n or #t
  for i = n, 2, -1 do
    local j = random(i)
    t[i], t[j] = t[j], t[i]
  end
end

-- Interpola ângulo pelo caminho mais curto.
function Util.angleLerp(a, b, t)
  local d = (b - a) % (math.pi * 2)
  if d > math.pi then d = d - math.pi * 2 end
  return a + d * t
end

-- Gira o ângulo `a` até `b` no máximo `step` radianos.
function Util.turnToward(a, b, step)
  local d = (b - a) % (math.pi * 2)
  if d > math.pi then d = d - math.pi * 2 end
  if d > step then d = step elseif d < -step then d = -step end
  return a + d
end

function Util.round(v)
  return floor(v + 0.5)
end

return Util
