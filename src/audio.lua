-- Fachada de áudio. Nesta versão é tudo no-op: as chamadas já estão
-- espalhadas nos lugares certos, basta carregar as Sources em `Audio.load`
-- e trocar o corpo de `Audio.play` para tocar de verdade.

local Audio = {
  enabled = false,   -- vire true quando houver arquivos em assets/sfx/
  sources = {},
}

-- IDs usados pelo jogo (documenta o que precisa existir depois):
-- "shot", "shot_spread", "shot_missile", "enemy_hit", "enemy_die",
-- "tank_die", "player_hit", "player_die", "pickup", "wave_start",
-- "wave_clear", "combo_lost", "menu_move", "menu_confirm", "menu_cancel"

function Audio.load()
  -- Exemplo de como plugar depois:
  -- Audio.sources.shot = love.audio.newSource("assets/sfx/shot.wav", "static")
end

function Audio.play(id, volume, pitch) -- luacheck: ignore
  if not Audio.enabled then return end
  local src = Audio.sources[id]
  if not src then return end
  local s = src:clone()
  s:setVolume(volume or 1)
  s:setPitch(pitch or 1)
  s:play()
end

function Audio.stopAll()
  if not Audio.enabled then return end
  love.audio.stop()
end

return Audio
