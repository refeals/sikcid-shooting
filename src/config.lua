-- Todas as constantes de tuning e cores do jogo.
-- Mexer AQUI para balancear dificuldade ou trocar a paleta; nenhum outro
-- arquivo deve conter número mágico de gameplay.

local Config = {}

-- ---------------------------------------------------------------------------
-- Geral
-- ---------------------------------------------------------------------------
Config.DEBUG = false          -- F1..F4 e overlay de FPS/entidades
Config.SMOKE = false          -- ligado por --smoke (teste automatizado)

Config.VIRTUAL_W = 640
Config.VIRTUAL_H = 360
Config.HUD_H = 40             -- faixa de HUD no topo; arena é o resto

-- Limites duros de entidades vivas (tamanho dos pools). Dimensionados para
-- hardware antigo; o que passar do teto é descartado sem alocar.
Config.MAX_ENEMIES = 100
Config.MAX_BULLETS = 200
Config.MAX_PARTICLES = 120
Config.MAX_PICKUPS = 24

-- Com DEBUG ligado: avisa no console quando o trabalho de um frame (update +
-- draw, sem contar a espera do vsync) passar deste tempo, dizendo qual
-- sistema pesou mais. Os avisos são espaçados para não inundar o console.
Config.PROFILE_WARN_MS = 8
Config.PROFILE_WARN_INTERVAL = 1.0   -- segundos entre avisos

-- ---------------------------------------------------------------------------
-- Cores (r, g, b, a de 0 a 1) -- trocar por sprites depois não mexe aqui,
-- mas a paleta de referência fica centralizada.
-- ---------------------------------------------------------------------------
Config.COLORS = {
  bg          = { 0.07, 0.07, 0.10, 1 },
  arenaBg     = { 0.11, 0.11, 0.15, 1 },
  arenaLine   = { 0.20, 0.20, 0.28, 1 },
  letterbox   = { 0.00, 0.00, 0.00, 1 },

  hudBg       = { 0.04, 0.04, 0.06, 1 },
  hudLine     = { 0.25, 0.25, 0.33, 1 },
  text        = { 0.90, 0.92, 1.00, 1 },
  textDim     = { 0.45, 0.47, 0.55, 1 },
  textWarn    = { 1.00, 0.78, 0.25, 1 },

  p1          = { 0.30, 0.62, 1.00, 1 },
  p2          = { 0.35, 0.90, 0.45, 1 },
  p1Dim       = { 0.15, 0.31, 0.50, 1 },
  p2Dim       = { 0.18, 0.45, 0.22, 1 },

  bullet      = { 1.00, 0.95, 0.55, 1 },
  bulletEnemy = { 1.00, 0.45, 0.75, 1 },

  grunt       = { 0.90, 0.30, 0.30, 1 },
  runner      = { 1.00, 0.55, 0.15, 1 },
  tank        = { 0.65, 0.35, 0.85, 1 },
  shooter     = { 0.95, 0.85, 0.30, 1 },

  door        = { 0.30, 0.30, 0.40, 1 },
  doorWarn    = { 1.00, 0.30, 0.30, 1 },

  flash       = { 1.00, 1.00, 1.00, 1 },
  orb         = { 0.60, 0.95, 1.00, 1 },
}

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------
Config.DEADZONE = 0.25        -- aplicada ao módulo do vetor, com renormalização
Config.EXIT_HOLD = 0.5        -- segundos de back+start (ou ESC) para sair do jogo
Config.EXIT_HOLD_BACK = 1.0   -- segundos de SELECT sozinho no gamepad para sair
Config.BIND_DEBOUNCE = 0.25   -- ignora o start que acabou de vincular o jogador
Config.AUTO_FIRE_ALWAYS = true

-- ---------------------------------------------------------------------------
-- Jogador
-- ---------------------------------------------------------------------------
Config.PLAYER = {
  radius = 7,
  size = 14,                  -- lado do quadrado desenhado
  speed = 160,                -- px/s
  accel = 1600,               -- px/s^2 (resposta rápida, sem patinar)
  lives = 3,
  maxLives = 5,
  invulnTime = 1.5,
  respawnTime = 3.0,
  blinkRate = 12,             -- piscadas por segundo durante invulnerabilidade
  muzzleTime = 0.05,          -- clarão do cano ao atirar
  spawnFxTime = 0.4,          -- anel de respawn
}

-- Arma base (modificada pelos power-ups via tabela de mods).
Config.WEAPON = {
  fireRate = 8,               -- tiros por segundo
  damage = 1,
  bulletSpeed = 420,
  bulletRadius = 3,
  bulletLife = 1.6,
  spreadCount = 3,
  spreadAngle = math.rad(20), -- leque total
  missileSpeed = 240,
  missileTurn = math.rad(200), -- correção de rota por segundo
  missileDamage = 3,
  orbCount = 2,
  orbRadius = 5,
  orbDistance = 26,
  orbSpeed = math.rad(200),
  orbDamage = 2,
  orbHitCooldown = 0.3,       -- por inimigo, evita matar tudo no mesmo frame
}

-- ---------------------------------------------------------------------------
-- Inimigos
-- ---------------------------------------------------------------------------
Config.ENEMIES = {
  grunt   = { hp = 1, speed = 58,  size = 12, radius = 6,  points = 100, color = "grunt",   contactDamage = true },
  runner  = { hp = 1, speed = 105, size = 10, radius = 5,  points = 150, color = "runner",  contactDamage = true,
              retargetMin = 0.6, retargetMax = 1.6, wobble = math.rad(50) },
  tank    = { hp = 6, speed = 32,  size = 22, radius = 11, points = 500, color = "tank",    contactDamage = true,
              push = 3.0 },
  shooter = { hp = 2, speed = 42,  size = 13, radius = 6,  points = 300, color = "shooter", contactDamage = true,
              keepDistance = 120, fireInterval = 1.8, bulletSpeed = 110, bulletLife = 4.0 },
}

Config.ENEMY_SEPARATION = 42    -- força de repulsão entre inimigos
Config.ENEMY_FLASH_TIME = 0.08  -- flash branco ao levar dano
Config.ENEMY_KNOCKBACK = 60
Config.GRID_CELL = 64           -- célula do grid espacial da broadphase

-- ---------------------------------------------------------------------------
-- Waves (curva infinita, sem tabela hardcoded)
-- ---------------------------------------------------------------------------
Config.WAVE = {
  telegraphTime = 0.4,        -- porta piscando antes do spawn
  bannerTime = 1.4,           -- "WAVE N" no centro ao começar
  restTime = 3.0,             -- respiro após limpar a wave
  clearBonus = 250,           -- multiplicado pelo número da wave
  batchMin = 1,
  batchMax = 3,               -- inimigos por spawn de porta
}

function Config.waveQuota(w)
  return math.floor(6 + 3 * w + 0.35 * w * w)
end

function Config.waveMaxAlive(w)
  return math.min(Config.MAX_ENEMIES, 8 + 2 * w)
end

function Config.waveSpawnInterval(w)
  return math.max(0.22, 1.10 - 0.045 * w)
end

-- Quantos inimigos saem por porta de cada vez. Cresce com a wave, senão o
-- telégrafo (0.4s por lote) limitaria a pressão a ~3 inimigos/s.
function Config.waveBatch(w)
  return Config.WAVE.batchMin, math.min(8, Config.WAVE.batchMax + math.floor(w / 6))
end

-- Pesos do mix de inimigos por wave; tipo só entra a partir de `from`.
Config.ENEMY_MIX = {
  { type = "grunt",   from = 1, base = 100, perWave = -4,  min = 25 },
  { type = "runner",  from = 2, base = 15,  perWave = 5,   min = 0 },
  { type = "shooter", from = 3, base = 10,  perWave = 4,   min = 0 },
  { type = "tank",    from = 5, base = 8,   perWave = 3,   min = 0 },
}

-- ---------------------------------------------------------------------------
-- Combo
-- ---------------------------------------------------------------------------
Config.COMBO = {
  window = 2.5,               -- timer que reseta a cada morte
  perMult = 5,                -- mortes necessárias por degrau de multiplicador
  maxMult = 8,
  lostMsgTime = 0.9,
  pulseTime = 0.35,           -- destaque ao subir de multiplicador
}

-- ---------------------------------------------------------------------------
-- Power-ups
-- ---------------------------------------------------------------------------
Config.POWERUP = {
  duration = 12,
  dropChance = 0.08,
  pickupRadius = 9,
  pickupSize = 12,
  pickupLife = 10,
  blinkAt = 3,                -- começa a piscar nos últimos N segundos
}

-- ---------------------------------------------------------------------------
-- Som
-- ---------------------------------------------------------------------------
-- Arquivos em assets/sfx/<id>.wav (ou .ogg). Som sem arquivo é ignorado em
-- silêncio, então dá para ir adicionando aos poucos.
--   vol      -- volume base (0..1), multiplicado por AUDIO.master
--   voices   -- cópias pré-carregadas: quantas instâncias tocam ao mesmo tempo
--   pitchVar -- variação aleatória de pitch (0.05 = +-5%): evita repetição robótica
--   minGap   -- intervalo mínimo entre dois disparos do mesmo som (s)
Config.AUDIO = {
  master = 0.8,
  dir = "assets/sfx/",
}

Config.SFX = {
  -- Tiros (tocam muito: volume baixo, várias vozes, throttle)
  shot          = { vol = 0.30, voices = 6, pitchVar = 0.06, minGap = 0.05 },
  shot_spread   = { vol = 0.32, voices = 6, pitchVar = 0.06, minGap = 0.05 },
  shot_missile  = { vol = 0.35, voices = 5, pitchVar = 0.05, minGap = 0.06 },
  shot_enemy    = { vol = 0.30, voices = 4, pitchVar = 0.08, minGap = 0.08 },
  -- Impacto e morte
  enemy_hit     = { vol = 0.35, voices = 4, pitchVar = 0.10, minGap = 0.04 },
  enemy_die     = { vol = 0.45, voices = 6, pitchVar = 0.12, minGap = 0.03 },
  tank_die      = { vol = 0.70, voices = 2, pitchVar = 0.05, minGap = 0.10 },
  player_die    = { vol = 0.80, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  player_spawn  = { vol = 0.50, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  -- Power-ups
  pickup        = { vol = 0.60, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  pickup_life   = { vol = 0.70, voices = 1, pitchVar = 0.00, minGap = 0.10 },
  powerup_end   = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  -- Waves e combo
  door_warn     = { vol = 0.30, voices = 4, pitchVar = 0.04, minGap = 0.12 },
  wave_start    = { vol = 0.60, voices = 1, pitchVar = 0.00, minGap = 0.50 },
  wave_clear    = { vol = 0.70, voices = 1, pitchVar = 0.00, minGap = 0.50 },
  combo_up      = { vol = 0.55, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  combo_lost    = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.20 },
  game_over     = { vol = 0.80, voices = 1, pitchVar = 0.00, minGap = 1.00 },
  -- Interface
  menu_move     = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  menu_confirm  = { vol = 0.55, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  menu_cancel   = { vol = 0.50, voices = 2, pitchVar = 0.00, minGap = 0.05 },
}

-- ---------------------------------------------------------------------------
-- Juice
-- ---------------------------------------------------------------------------
Config.JUICE = {
  shakeEnemyDeath = 0.8,
  shakePlayerDeath = 7.0,
  shakeTankDeath = 3.0,
  shakeDecay = 12,
  hitStopTank = 0.05,
  deathParticles = 8,
  tankDeathParticles = 18,
  playerDeathParticles = 24,
  particleSpeedMin = 40,
  particleSpeedMax = 170,
  particleLifeMin = 0.25,
  particleLifeMax = 0.6,
  particleSize = 4,
  particleDrag = 2.6,
}

return Config
