-- Pool genérico de objetos com teto fixo.
--
-- Todos os objetos vivem num único array `items`. Os vivos ocupam 1..count;
-- os livres ficam parados depois de `count` e são reaproveitados sem realocar.
-- Nenhuma tabela é criada ou descartada depois que o pool enche.
--
-- Iteração correta (permite remover durante o loop):
--   local i = 1
--   while i <= pool.count do
--     local o = pool.items[i]
--     if morreu then pool:release(i) else i = i + 1 end
--   end

local Pool = {}
Pool.__index = Pool

-- factory: função que cria um objeto vazio. capacity: teto duro de vivos.
function Pool.new(factory, capacity)
  return setmetatable({
    items = {},
    count = 0,       -- vivos
    allocated = 0,   -- já criados (vivos + parados)
    capacity = capacity,
    factory = factory,
    peak = 0,        -- pico de vivos (debug/smoke)
    denied = 0,      -- pedidos recusados por teto (debug/smoke)
  }, Pool)
end

-- Devolve um objeto pronto para ser reinicializado, ou nil se estourou o teto.
function Pool:acquire()
  if self.count < self.allocated then
    self.count = self.count + 1
  elseif self.allocated < self.capacity then
    self.allocated = self.allocated + 1
    self.count = self.allocated
    self.items[self.count] = self.factory()
  else
    self.denied = self.denied + 1
    return nil
  end
  if self.count > self.peak then self.peak = self.count end
  return self.items[self.count]
end

-- Devolve ao pool o objeto do índice `i` (swap-remove, O(1)).
function Pool:release(i)
  local items = self.items
  local last = self.count
  items[i], items[last] = items[last], items[i]
  self.count = last - 1
end

function Pool:clear()
  self.count = 0
end

function Pool:isFull()
  return self.count >= self.capacity
end

return Pool
