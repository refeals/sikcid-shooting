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

-- Per-slot player colors. Every player-owned visual (ship, shots, HUD lives,
-- lobby slot) reads its color from here, so a future color picker only has to
-- write into this list.
Config.PLAYER_COLORS = { Config.COLORS.p1, Config.COLORS.p2 }
Config.PLAYER_COLORS_DIM = { Config.COLORS.p1Dim, Config.COLORS.p2Dim }

-- ---------------------------------------------------------------------------
-- Art (Kenney packs, CC0)
-- ---------------------------------------------------------------------------
-- All gameplay still runs in 640x360 logical coordinates. The screen canvas is
-- rendered at an integer multiple of that (see src/screen.lua), so sprites stay
-- smooth on 720p/1080p while the logic is untouched.
Config.ART = {
  -- Caps the render multiplier (nil = as large as the window allows). Lower it
  -- to 2 if fill rate becomes a problem on weak hardware: the final blit then
  -- upscales with linear filtering.
  maxRenderScale = nil,

  -- Sprite sheets: Kenney XML atlases. Sprite names drop the ".png".
  sheets = {
    ss2    = { image = "assets/art/spaceShooter2_spritesheet.png", atlas = "assets/art/spaceShooter2_spritesheet.xml" },
    simple = { image = "assets/art/simpleSpace_sheet.png",         atlas = "assets/art/simpleSpace_sheet.xml" },
  },
  uiDir = "assets/art/UIPack/",

  -- Role -> "sheet:sprite". Every role is extracted once at boot (nothing is
  -- created during gameplay). `rot` is the sprite's own facing in radians
  -- (Kenney ships point down = pi/2), subtracted when aiming it.
  sprites = {
    playerShip   = { "ss2:spaceShips_002", rot = math.pi / 2 },
    engineFlame1 = { "ss2:spaceEffects_001", rot = -math.pi / 2 },
    engineFlame2 = { "ss2:spaceEffects_002", rot = -math.pi / 2 },
    orb          = { "ss2:spaceParts_080" },
    shot         = { "ss2:spaceMissiles_012", rot = -math.pi / 2 },
    missile      = { "ss2:spaceMissiles_003", rot = -math.pi / 2 },
    enemyShot    = { "simple:star_small" },
    grunt        = { "simple:enemy_A", rot = -math.pi / 2 },
    runner       = { "simple:ship_B", rot = -math.pi / 2 },
    shooter      = { "simple:enemy_D", rot = -math.pi / 2 },
    tank         = { "simple:station_C" },
    puff1        = { "ss2:spaceEffects_009" },
    puff2        = { "ss2:spaceEffects_011" },
    puff3        = { "ss2:spaceEffects_013" },
    puff4        = { "ss2:spaceEffects_015" },
    starTiny     = { "simple:star_tiny" },
    starSmall    = { "simple:star_small" },
    door         = { "ss2:spaceStation_003", rot = math.pi / 2 },  -- long side = wall
    doorLight    = { "ss2:spaceBuilding_004" },
    iconPlus     = { "simple:icon_plusSmall" },
  },

  -- On-screen size (logical px, longest side) of each sprite. Hitboxes stay in
  -- Config.PLAYER / ENEMIES / WEAPON: sprites are drawn larger than the
  -- collision circle for readability, never the other way around.
  size = {
    playerShip = 24,
    engineFlame = 12,
    orb = 10,
    shot = 8,
    missile = 15,
    enemyShot = 10,
    grunt = 20,
    runner = 17,
    shooter = 22,
    tank = 38,
    pickup = 14,
    hudLife = 9,
  },
  -- Arena background (src/starfield.lua). Fixed seed: same sky every match.
  stars = {
    seed = 1337,
    count = 80,
    bigShare = 0.12,          -- fraction drawn with the bigger star sprite
    tinyMin = 2, tinyMax = 4,
    bigMin = 4, bigMax = 7,
    alphaMin = 0.25, alphaMax = 0.7,
    twinkleShare = 0.35,
    twinkleSpeed = 2.2,
    color = { 0.75, 0.80, 1.00 },
  },
  gridAlpha = 0.18,           -- the 40px arena grid, kept faint under the stars
  door = { thick = 18, light = 7 },  -- hatch depth into the arena / light size
  enemyTurnRate = 10,     -- how fast enemy sprites ease toward their heading
  tankSpin = 0.8,         -- rad/s: the tank (a station) slowly rotates in place
  enemyShotSpin = 6,      -- rad/s: enemy star shots spin

  -- UIPack art is authored large (a panel is 64px); 1 texel = this many
  -- logical px. 0.5 makes it exactly 1:1 on a 1280x720 render.
  uiScale = 0.5,

  -- UIPack panels are light grey; they are tinted down to dark glass so the
  -- HUD and menus sit on the dark arena without glare.
  ui = {
    panel = { 0.16, 0.18, 0.25, 0.90 },
    panelLight = { 0.28, 0.30, 0.40, 0.95 },
    neutral = { 0.55, 0.57, 0.66, 1 },   -- tab color for screens owned by no one
    tabH = 12,
  },

  -- Kenney pixel fonts sit on an 8px grid: only multiples of 8 keep every
  -- stroke the same width. Sizes here must stay multiples of 8.
  fonts = {
    titleSmall = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 8 },
    title = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 16 },
    big   = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 24 },
    body  = { file = "assets/art/Fonts/Kenney Mini Square.ttf", size = 8 },
    large = { file = "assets/art/Fonts/Kenney Mini Square.ttf", size = 16 },
    mono  = { file = "assets/art/Fonts/Kenney Mini Square Mono.ttf", size = 8 },
    monoLarge = { file = "assets/art/Fonts/Kenney Mini Square Mono.ttf", size = 16 },
  },

  -- Palette-swap shader (src/shaders.lua): which texels count as "Kenney red"
  -- and the red channel value of its base tone (172/255).
  recolor = { redMin = 0.10, redMax = 0.25, baseRed = 0.675 },
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
  -- Visual only (no gameplay effect):
  turnRate = 18,              -- how fast the drawn ship eases toward the aim
  flameMinSpeed = 20,         -- px/s above which the engine flame shows
  reticleDistance = 20,       -- px from the ship center to the aim reticle
  reticleSize = 9,            -- reticle width (px)
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
  pickupRadius = 9,           -- drawn size lives in Config.ART.size.pickup
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
-- Música
-- ---------------------------------------------------------------------------
-- Arquivos em assets/music/<nome>.ogg (ou .wav), tocados em streaming (não
-- ocupam a RAM toda). Cada tela pede um PAPEL; o papel aponta para uma faixa.
-- Dois papéis na mesma faixa = a música continua sem reiniciar ao trocar.
Config.MUSIC = {
  dir = "assets/music/",
  volume = 0.45,          -- abaixo dos efeitos, para tiros/explosões se destacarem
  duck = 0.3,             -- fração do volume durante a pausa
  fadeTime = 0.6,         -- crossfade entre faixas (s)
  gameOverDelay = 2.5,    -- silêncio no game over antes da música de menu voltar
  tracks = {
    menu = "danse-contemporaine",   -- lobby, briefing, game over
    game = "danse-contemporaine",   -- arena
  },
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
  -- Explosions = smoke puffs + sparks, all from the same particle pool.
  deathParticles = 5,
  deathPuffs = 3,
  tankDeathParticles = 10,
  tankDeathPuffs = 7,
  playerDeathParticles = 14,
  playerDeathPuffs = 7,
  puffSpeedMin = 10,
  puffSpeedMax = 45,
  puffLifeMin = 0.35,
  puffLifeMax = 0.65,
  puffGrow = 0.8,             -- extra size reached at the end of the life
  puffAlpha = 0.85,
  puffSpin = 2.0,             -- max rad/s
  -- Missile smoke trail: only emitted while the pool is below trailPoolShare
  -- of its size, so trails never starve explosions of particles.
  trailInterval = 0.07,
  trailLife = 0.3,
  trailSize = 6,
  trailPoolShare = 0.6,
  particleSpeedMin = 40,
  particleSpeedMax = 170,
  particleLifeMin = 0.25,
  particleLifeMax = 0.6,
  particleSize = 4,
  particleDrag = 2.6,
}

return Config
