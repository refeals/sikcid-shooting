-- Todas as constantes de tuning e cores do jogo.
-- Mexer AQUI para balancear dificuldade ou trocar a paleta; nenhum outro
-- arquivo deve conter número mágico de gameplay.

local Config = {}

-- ---------------------------------------------------------------------------
-- Geral
-- ---------------------------------------------------------------------------
Config.DEBUG = false          -- F1..F4 e overlay de FPS/entidades
Config.SMOKE = false          -- ligado por --smoke (teste automatizado)
Config.WEB = love.system.getOS() == "Web"   -- browser build (love.js, itch.io)

Config.VIRTUAL_W = 640
Config.VIRTUAL_H = 360
Config.HUD_H = 48             -- faixa de HUD no topo; arena é o resto

-- Limites duros de entidades vivas (tamanho dos pools). Dimensionados para
-- hardware antigo; o que passar do teto é descartado sem alocar.
Config.MAX_ENEMIES = 100
Config.MAX_BULLETS = 320
-- (Particles: the pool size depends on the FX quality, Config.FX.particles.)
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
  arenaLine   = { 0.20, 0.20, 0.28, 1 },
  letterbox   = { 0.00, 0.00, 0.00, 1 },

  hudBg       = { 0.04, 0.04, 0.06, 1 },
  hudLine     = { 0.25, 0.25, 0.33, 1 },
  text        = { 0.90, 0.92, 1.00, 1 },
  textDim     = { 0.45, 0.47, 0.55, 1 },
  textWarn    = { 1.00, 0.78, 0.25, 1 },

  bullet     = { 1.00, 0.95, 0.55, 1 },
  bulletEnemy = { 1.00, 0.45, 0.75, 1 },

  grunt       = { 0.90, 0.30, 0.30, 1 },
  runner      = { 1.00, 0.55, 0.15, 1 },
  tank        = { 0.65, 0.35, 0.85, 1 },
  shooter     = { 0.95, 0.85, 0.30, 1 },
  kamikaze    = { 0.85, 0.12, 0.32, 1 },   -- crimson (not the enemy-shot pink)
  divisor     = { 0.20, 0.85, 0.70, 1 },   -- aqua (its fragments too)
  sniper      = { 0.55, 0.68, 0.90, 1 },   -- steel blue
  carrier     = { 0.92, 0.88, 0.76, 1 },   -- ivory (its scouts too)

  door        = { 0.30, 0.30, 0.40, 1 },
  doorWarn    = { 1.00, 0.30, 0.30, 1 },

  flash       = { 1.00, 1.00, 1.00, 1 },
}
-- The sniper's streak glows in the danger red of the aim lines.
Config.COLORS.sniperShot = Config.COLORS.doorWarn

-- Colors a player can pick in the lobby (left/right cycles, Y picks one at
-- random). Kept clear of the enemy-shot pink. `name` is shown in the lobby.
Config.PLAYER_PALETTE = {
  { name = "AZUL",    color = { 0.30, 0.62, 1.00, 1 } },
  { name = "VERDE",   color = { 0.35, 0.90, 0.45, 1 } },
  { name = "CIANO",   color = { 0.25, 0.90, 0.95, 1 } },
  { name = "LIMA",    color = { 0.75, 0.95, 0.25, 1 } },
  { name = "BRANCO",  color = { 0.92, 0.94, 1.00, 1 } },
  { name = "LARANJA", color = { 1.00, 0.60, 0.20, 1 } },
  { name = "LILÁS",   color = { 0.72, 0.55, 1.00, 1 } },
  { name = "DOURADO", color = { 1.00, 0.84, 0.30, 1 } },
}
-- Palette index each slot starts with when the save has no choice yet.
Config.PLAYER_DEFAULT_COLOR = { 1, 2 }

-- Runtime per-slot player colors. Every player-owned visual (ship, shots, HUD
-- lives, lobby slot, pause, game over) reads its color from here; the lobby
-- writes the picked palette colors into this list.
Config.PLAYER_COLORS = {
  Config.PLAYER_PALETTE[Config.PLAYER_DEFAULT_COLOR[1]].color,
  Config.PLAYER_PALETTE[Config.PLAYER_DEFAULT_COLOR[2]].color,
}

-- Lobby color picker.
Config.LOBBY = {
  stickThreshold = 0.5,   -- left stick x past this counts as a left/right press
  arrowSize = 6,          -- picker arrow height (px)
  arrowGap = 30,          -- arrow distance from the ship preview center (px)
}

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
    -- Same pack at 2x, for sprites drawn big (the bosses): the 1x ships would
    -- be upscaled 1.5-2.3x and blur. Its sprite NUMBERS differ from the 1x
    -- sheet; match them by size (2x = double the 1x width/height).
    ss2x   = { image = "assets/art/spaceShooter2_spritesheet_2X.png", atlas = "assets/art/spaceShooter2_spritesheet_2X.xml" },
    simple = { image = "assets/art/simpleSpace_sheet.png",         atlas = "assets/art/simpleSpace_sheet.xml" },
  },
  uiDir = "assets/art/UIPack/",

  -- Role -> "sheet:sprite". Every role is extracted once at boot (nothing is
  -- created during gameplay). `rot` is the sprite's own facing in radians
  -- (Kenney ships point down = pi/2), subtracted when aiming it. `grey`
  -- converts the sprite to white-based greyscale so setColor tints it exactly
  -- (the engine flame takes the player's color).
  sprites = {
    playerShip   = { "ss2:spaceShips_002", rot = math.pi / 2 },
    -- Same ship, alpha dilated by `outline` texels into a white silhouette:
    -- the arena outline (see Config.ART.outline). The ship is 101 texels wide
    -- drawn at 24px, so 1 texel ~ 0.24 logical px. Wider outlines also fill
    -- the gaps between the ship's wings and body (5 already turns it solid).
    playerOutline = { "ss2:spaceShips_002", rot = math.pi / 2, outline = 4 },
    engineFlame1 = { "ss2:spaceEffects_001", rot = -math.pi / 2, grey = true },
    engineFlame2 = { "ss2:spaceEffects_002", rot = -math.pi / 2, grey = true },
    drone        = { "ss2:spaceParts_080" },   -- DRONE power-up, tinted with the player color
    shot         = { "ss2:spaceMissiles_012", rot = -math.pi / 2 },
    missile      = { "ss2:spaceMissiles_003", rot = -math.pi / 2 },
    enemyShot    = { "simple:star_small" },
    grunt        = { "simple:enemy_A", rot = -math.pi / 2 },
    runner       = { "simple:ship_B", rot = -math.pi / 2 },
    shooter      = { "simple:enemy_D", rot = -math.pi / 2 },
    tank         = { "simple:station_C" },
    kamikaze     = { "simple:ship_G", rot = -math.pi / 2 },   -- a sharp dart
    divisor      = { "simple:enemy_E", rot = -math.pi / 2 },  -- a cluster of pods
    fragment     = { "simple:ship_A", rot = -math.pi / 2 },
    sniper       = { "simple:ship_I", rot = -math.pi / 2 },   -- long and thin
    carrier      = { "simple:ship_sidesB", rot = -math.pi / 2 },  -- wide, side pods
    scout        = { "simple:ship_D", rot = -math.pi / 2 },   -- carrier drones
    puff1        = { "ss2:spaceEffects_009" },
    puff2        = { "ss2:spaceEffects_011" },
    puff3        = { "ss2:spaceEffects_013" },
    puff4        = { "ss2:spaceEffects_015" },
    starTiny     = { "simple:star_tiny" },
    starSmall    = { "simple:star_small" },
    -- Background (src/background.lua). Never reuse enemy or player sprites
    -- here: the sky must not be mistaken for something that can hurt you.
    starGlint    = { "simple:star_large" },                           -- 4-point sparkle
    streak       = { "simple:effect_yellow", rot = -math.pi / 2, grey = true },  -- shooting star, head up
    -- Distant objects: `grey` so all of them take the theme's object color
    -- the same way (a colored sprite darkened reads as a hole in the sky).
    bgMeteor     = { "ss2:spaceMeteors_004", grey = true },
    bgRock       = { "simple:meteor_detailedLarge" },
    bgRockSquare = { "simple:meteor_squareDetailedLarge" },
    bgSatellite  = { "simple:satellite_A" },
    bgSatellite2 = { "simple:satellite_C" },
    bgPanels     = { "ss2:spaceBuilding_015", grey = true },
    bgStation    = { "ss2:spaceStation_021", grey = true },
    bgShip       = { "ss2:spaceShips_008", rot = math.pi / 2, grey = true },
    -- Bosses (Config.BOSS.variants): big red/white Kenney ships from the 2x
    -- sheet, recolored per variant. 1x equivalents in the comments; never the
    -- player's ship (1x 002 = 2x 009) nor the sky's distant ship (1x 008 =
    -- 2x 006).
    boss1        = { "ss2x:spaceShips_005", rot = math.pi / 2 },  -- 1x 007
    boss2        = { "ss2x:spaceShips_002", rot = math.pi / 2 },  -- 1x 004
    boss3        = { "ss2x:spaceShips_004", rot = math.pi / 2 },  -- 1x 006
    boss4        = { "ss2x:spaceShips_003", rot = math.pi / 2 },  -- 1x 005
    boss5        = { "ss2x:spaceShips_007", rot = math.pi / 2 },  -- 1x 009
    door         = { "ss2:spaceStation_003", rot = math.pi / 2 },  -- long side = wall
    doorLight    = { "ss2:spaceBuilding_004" },
    iconPlus     = { "simple:icon_plusSmall" },
  },

  -- On-screen size (logical px, longest side) of each sprite. Hitboxes stay in
  -- Config.PLAYER / ENEMIES / WEAPON: sprites are drawn larger than the
  -- collision circle for readability, never the other way around.
  size = {
    playerShip = 24,
    engineFlame = 18,         -- outer flame, tinted with the player color
    engineCore = 10,          -- white-hot core drawn over it
    drone = 9,
    salvo = 18,               -- respawn support missiles
    shot = 8,
    missile = 15,
    bossMissile = 18,
    enemyShot = 10,
    grunt = 20,
    runner = 17,
    shooter = 22,
    tank = 38,
    kamikaze = 18,
    divisor = 22,
    fragment = 10,
    sniper = 18,
    carrier = 32,
    scout = 9,
    sniperShot = 14,        -- length of the sniper's streak
    pickup = 14,
    hudLife = 9,
  },
  -- Sky behind the arena and the menus (src/background.lua). Every ambient
  -- motion is a function of the clock and a fixed seed: no per-frame state,
  -- same sky every match. Speeds in logical px/s.
  background = {
    seed = 1337,
    drift = { -0.8, 0.6 },    -- shared drift direction (normalized at load)
    parallaxEase = 2.5,       -- how fast the parallax follows the players (1/s)
    -- Star layers, back to front. `parallax` = fraction of the players'
    -- offset from the arena center the layer moves against (depth cue).
    layers = {
      { count = 70, bigShare = 0,    tinyMin = 1.5, tinyMax = 3,   bigMin = 0, bigMax = 0,
        alphaMin = 0.15, alphaMax = 0.45, speed = 2.5, parallax = 0.006 },
      { count = 26, bigShare = 0.25, tinyMin = 2.5, tinyMax = 4,   bigMin = 3.5, bigMax = 5,
        alphaMin = 0.30, alphaMax = 0.65, speed = 6,   parallax = 0.015 },
      { count = 10, bigShare = 1,    tinyMin = 0,   tinyMax = 0,   bigMin = 5, bigMax = 7,
        alphaMin = 0.55, alphaMax = 0.85, speed = 11,  parallax = 0.025 },
    },
    twinkleShare = 0.35,
    twinkleSpeed = 2.2,
    -- Nebula: two cloud textures baked from noise at load, tinted with the
    -- theme's two nebula colors, drawn additive and breathing slowly. The
    -- bake keeps the arena center darker than the edges.
    nebula = {
      texW = 160, texH = 90,  -- baked texture size (stretched to the screen)
      alpha = 0.16,
      sway = 18,              -- px the clouds wander around
      swayRate = 0.05,        -- rad/s of that wander
      breathe = 0.05,         -- scale amplitude
    },
    -- Sparkles: a few 4-point glints, each lighting up a random mid/near star.
    -- Kept smaller and slower-spinning than the enemy star shots, and every
    -- theme's star color stays near white (never the enemy-shot pink).
    sparkle = { slots = 3, periodMin = 2.2, periodMax = 4.5, life = 0.7,
                sizeMin = 7, sizeMax = 11, alpha = 0.85, spin = 0.5 },
    -- Shooting stars: time is cut into slots; some slots get one.
    shootingStar = { slot = 6, chance = 0.7, life = 0.6, travelMin = 140, travelMax = 230,
                     length = 46, width = 2.5, alpha = 0.55, spread = 1.0 },
    -- Distant objects crossing the sky, dark silhouettes (theme `obj` color).
    -- Time is cut into slots; some slots launch one, from a random edge.
    objects = {
      slot = 40, chance = 0.85, parallax = 0.01,
      kinds = {
        { role = "bgMeteor",     sizeMin = 30, sizeMax = 46, spin = 0.12, lifeMin = 45, lifeMax = 70 },
        { role = "bgRock",       sizeMin = 18, sizeMax = 28, spin = 0.25, lifeMin = 35, lifeMax = 55 },
        { role = "bgRockSquare", sizeMin = 18, sizeMax = 26, spin = 0.25, lifeMin = 35, lifeMax = 55 },
        { role = "bgSatellite",  sizeMin = 20, sizeMax = 26, spin = 0.10, lifeMin = 45, lifeMax = 70 },
        { role = "bgSatellite2", sizeMin = 20, sizeMax = 26, spin = 0.10, lifeMin = 45, lifeMax = 70 },
        { role = "bgPanels",     sizeMin = 38, sizeMax = 48, spin = 0.06, lifeMin = 50, lifeMax = 70 },
        { role = "bgStation",    sizeMin = 52, sizeMax = 64, spin = 0.04, lifeMin = 55, lifeMax = 70 },
        -- A ship far away: small, straight line, fast, faces where it goes.
        { role = "bgShip",       sizeMin = 14, sizeMax = 17, ship = true, lifeMin = 9, lifeMax = 14 },
      },
    },
    -- Arena grid, with ripples on big moments (wave start/clear, tank death).
    grid = {
      cell = 40, alpha = 0.18,
      pulseSpeed = 300,       -- px/s the ring grows
      pulseLife = 1.4,        -- s until a ring is gone
      pulseWidth = 16,        -- ring thickness (px)
      pulseFill = 0.06,       -- faint glow between the lines under the ring
      waveStart = 0.50, waveClear = 0.35, tankDeath = 0.70,  -- ring strengths
    },
    -- One planet per theme, built at load from Kenney Planets parts
    -- (assets/art/planets/, the used subset of PlanetParts/): a tinted
    -- sphere, tinted surface patterns, then a light map multiplied on top
    -- (~25% grey night side, white lit side). It sits big in a corner, cut by
    -- the screen edge; `brightness` keeps the night side near the sky color so
    -- mostly the lit crescent shows. The lit side is turned to face the
    -- screen center; `lightDir` is where each light map's lit side points as
    -- authored (radians, 0 = right, pi/2 = down).
    planets = {
      dir = "assets/art/planets/",
      bake = 512,             -- baked texture size (px)
      brightness = 0.45,
      parallax = 0.004,
      bob = 1.5,              -- px of slow drift
      bobRate = 0.15,         -- rad/s
      lightDir = { light0 = math.pi / 4, light3 = math.pi / 2 },
    },
    -- Sky palette, fading over `themeFade` seconds. The boss waves (every
    -- Config.BOSS.every) use `bossTheme`; the blocks of waves between them
    -- cycle through `themes` (waves 1-9 theme 1, 11-19 theme 2...), and the
    -- next block's palette comes in as the boss dies. bg = base fill;
    -- nebulaA/B = cloud tints; star = stars, glints and shooting stars; obj =
    -- distant object silhouettes; grid = grid lines; planet = see `planets`
    -- above (x, y = center and size = diameter in logical px; layers =
    -- { part, color, alpha, rotation }). Red is kept for the boss theme only.
    themeFade = 2.5,
    bossTheme = { -- danger: blood red, a dying red star at the top right
      bg = { 0.15, 0.04, 0.05 }, nebulaA = { 0.95, 0.18, 0.12 }, nebulaB = { 0.80, 0.35, 0.08 },
      star = { 1.00, 0.88, 0.84 }, obj = { 0.30, 0.10, 0.10 }, grid = { 0.42, 0.12, 0.12 },
      planet = { x = 610, y = 80, size = 280, sphere = "sphere2", base = { 0.85, 0.20, 0.12 },
                 layers = { { "noise00", { 0.40, 0.05, 0.05 }, 0.9, 0 },
                            { "noise10", { 1.00, 0.55, 0.20 }, 0.30, 0.3 } }, light = "light0" } },
    themes = {
      { -- deep violet: lilac banded gas giant, bottom left
        bg = { 0.11, 0.11, 0.15 }, nebulaA = { 0.35, 0.30, 0.85 }, nebulaB = { 0.75, 0.30, 0.70 },
        star = { 0.75, 0.80, 1.00 }, obj = { 0.20, 0.21, 0.30 }, grid = { 0.20, 0.20, 0.28 },
        planet = { x = -30, y = 372, size = 300, sphere = "sphere1", base = { 0.45, 0.38, 0.85 },
                   layers = { { "noise08", { 0.80, 0.70, 1.00 }, 0.55, 0 } }, light = "light0" } },
      { -- teal / emerald: ocean world with continents and clouds, top right
        bg = { 0.07, 0.12, 0.13 }, nebulaA = { 0.15, 0.75, 0.62 }, nebulaB = { 0.25, 0.50, 0.95 },
        star = { 0.75, 1.00, 0.92 }, obj = { 0.14, 0.24, 0.25 }, grid = { 0.16, 0.28, 0.30 },
        planet = { x = 650, y = 75, size = 260, sphere = "sphere0", base = { 0.20, 0.45, 0.85 },
                   layers = { { "noise19", { 0.30, 0.80, 0.50 }, 0.8, 0 },
                              { "noise10", { 1.00, 1.00, 1.00 }, 0.25, 0.6 } }, light = "light0" } },
      { -- olive / chartreuse: mossy spotted world, bottom right
        bg = { 0.09, 0.11, 0.07 }, nebulaA = { 0.60, 0.80, 0.20 }, nebulaB = { 0.25, 0.60, 0.35 },
        star = { 0.92, 1.00, 0.85 }, obj = { 0.19, 0.24, 0.14 }, grid = { 0.24, 0.30, 0.16 },
        planet = { x = 670, y = 360, size = 300, sphere = "sphere2", base = { 0.55, 0.65, 0.25 },
                   layers = { { "noise00", { 0.28, 0.38, 0.10 }, 0.9, 0 } }, light = "light3" } },
      { -- amber / rust: orange with brown bands, top left
        bg = { 0.12, 0.10, 0.07 }, nebulaA = { 0.95, 0.55, 0.20 }, nebulaB = { 0.80, 0.28, 0.18 },
        star = { 1.00, 0.92, 0.78 }, obj = { 0.27, 0.21, 0.15 }, grid = { 0.30, 0.25, 0.18 },
        planet = { x = -20, y = 65, size = 240, sphere = "sphere1", base = { 1.00, 0.65, 0.30 },
                   layers = { { "noise07", { 0.70, 0.30, 0.12 }, 0.85, 0 } }, light = "light0" } },
      { -- ice: white with blue frost spots, rising from the bottom
        bg = { 0.08, 0.11, 0.16 }, nebulaA = { 0.40, 0.80, 1.00 }, nebulaB = { 0.75, 0.85, 1.00 },
        star = { 0.85, 0.95, 1.00 }, obj = { 0.18, 0.24, 0.32 }, grid = { 0.20, 0.28, 0.38 },
        planet = { x = 130, y = 425, size = 280, sphere = "sphere1", base = { 0.80, 0.90, 1.00 },
                   layers = { { "noise27", { 0.50, 0.70, 0.95 }, 0.8, 0 } }, light = "light3" } },
    },
  },
  door = { thick = 18, light = 7 },  -- hatch depth into the arena / light size
  -- Player outline in the arena (not in the lobby or HUD): the player's color
  -- mixed toward white by `lighten`, alpha pulsing gently around `alpha` so
  -- the ship stands out in the chaos without blinking.
  outline = { lighten = 0.45, alpha = 0.85, pulseAmp = 0.15, pulseRate = 3 },
  -- Player engine flame (additive): two frames flickering, stretched longer
  -- the faster the ship moves (stretchMin at flameMinSpeed, stretchMax at
  -- full speed).
  engine = { flickerRate = 20, coreAlpha = 0.9, stretchMin = 0.8, stretchMax = 1.25 },
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
    -- Window title tab height. Rocket Square 16 caps are 10px, about half the
    -- tab, the same proportion the old 12px tab had with the 8px font. The
    -- tab's bevel takes ~4px top and bottom, so accents and cedillas ("Ã",
    -- "Ç") would sit on it: keep tab titles unaccented.
    tabH = 22,
    tabFont = "title",                   -- window title tab font role
    hudTab = { w = 24, h = 14 },         -- the "P1"/"P2" tab in the 40px HUD strip
  },

  -- Kenney pixel fonts sit on an 8px grid: only multiples of 8 keep every
  -- stroke the same width. Sizes here must stay multiples of 8.
  fonts = {
    titleSmall = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 8 },
    title = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 16 },
    big   = { file = "assets/art/Fonts/Kenney Rocket Square.ttf", size = 24 },
    body  = { file = "assets/art/Fonts/Kenney Mini Square.ttf", size = 8 },
    large = { file = "assets/art/Fonts/Kenney Mini Square.ttf", size = 16 },
    -- Numbers. Kenney Mini (not the Square cut): its chamfered "0" reads as a
    -- zero, where the Square fonts draw a plain box. It is not monospaced, so
    -- it is drawn with UI.digits (fixed cell per digit). One size per text
    -- size it sits next to: body 8, title 16, big 24 (see UI.textNumber).
    digitsSmall = { file = "assets/art/Fonts/Kenney Mini.ttf", size = 8 },
    digits      = { file = "assets/art/Fonts/Kenney Mini.ttf", size = 16 },
    digitsBig   = { file = "assets/art/Fonts/Kenney Mini.ttf", size = 24 },
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

-- Auto-aim: with no manual aim (right stick / d-pad), the ship aims and fires
-- at the nearest enemy whose center is on screen (world:isOnScreen); with
-- none visible it holds fire.
Config.AUTO_AIM = {
  enabled = true,      -- false = fire only while aiming by hand (stick / d-pad)
  switchRatio = 0.75,  -- another enemy steals the lock only when closer than
                       -- this fraction of the locked enemy's distance
}

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

-- Dash (RB / LB / B, Shift, touch button): a quick burst along the move stick
-- (or the aim, standing still) that passes through enemies and their shots.
--   distance/time -- px covered in s (the ship keeps firing meanwhile)
--   cooldown      -- s from one dash start to the next
--   grace         -- s of protection left after the burst ends
--   lingerMax     -- ending inside an enemy (or the boss): the protection
--                    holds while still touching it, at most this many s more
--   buffer        -- a press up to this many s early fires once it is ready
-- Visuals: `ghosts` fading copies of the ship sampled every `ghostEvery` s
-- during the burst, gone after `ghostLife` s; the cooldown ring around the
-- ship (`ring.radius` x ship size) and its flash when ready.
Config.DASH = {
  distance = 70,
  time = 0.15,
  cooldown = 1.2,
  grace = 0.1,
  lingerMax = 0.3,
  buffer = 0.1,
  ghosts = 4, ghostEvery = 0.03, ghostLife = 0.22, ghostAlpha = 0.45,
  ring = { radius = 0.85, width = 1.5, alpha = 0.35 },
  readyFlash = 0.18,
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
}

-- ---------------------------------------------------------------------------
-- Inimigos
-- ---------------------------------------------------------------------------
Config.ENEMIES = {
  grunt   = { hp = 1, speed = 58,  size = 12, radius = 6,  points = 100, color = "grunt",   contactDamage = true },
  runner  = { hp = 1, speed = 105, size = 10, radius = 5,  points = 150, color = "runner",  contactDamage = true,
              retargetMin = 0.6, retargetMax = 1.6, wobble = math.rad(50) },
  tank    = { hp = 6, speed = 32,  size = 22, radius = 11, points = 500, color = "tank",    contactDamage = true,
              push = 3.0, hpBar = true },
  shooter = { hp = 2, speed = 42,  size = 13, radius = 6,  points = 300, color = "shooter", contactDamage = true,
              keepDistance = 120, fireInterval = 1.8, bulletSpeed = 110, bulletLife = 4.0 },
  -- Chases (slower than a grunt) to `aimRange` px, stops and aims for
  -- `aimTime` s along a red line (it follows the target until the last
  -- `lockTime` s, then freezes), then charges at `chargeSpeed` for up to
  -- `chargeTime` s through the other enemies. Hitting a wall stuns it for
  -- `stunTime` s (spinning at `stunSpin` rad/s). `name` = debut banner.
  kamikaze = { hp = 2, speed = 48, size = 12, radius = 6, points = 200, color = "kamikaze", contactDamage = true,
               name = "KAMIKAZE", aimRange = 150, aimTime = 0.5, lockTime = 0.15,
               chargeSpeed = 320, chargeTime = 0.9, reach = 288, stunTime = 1.0, stunSpin = 12,
               lineAlpha = 0.55, lineWidth = 1.5, sparkEvery = 0.15 },
  -- Dies into `splitCount` `splitInto` enemies fanned out at `splitSpeed`.
  divisor  = { hp = 3, speed = 45, size = 16, radius = 8, points = 250, color = "divisor", contactDamage = true,
               name = "DIVISOR", splitInto = "fragment", splitCount = 3, splitSpeed = 110 },
  -- The divisor's pieces: fly out harmless for `harmlessTime` s, then act
  -- like small runners. Spawned outside the wave quota; never split again.
  fragment = { hp = 1, speed = 120, size = 8, radius = 4, points = 50, color = "divisor", contactDamage = true,
               harmlessTime = 0.3, retargetMin = 0.6, retargetMax = 1.6, wobble = math.rad(40) },
  -- Takes a spot `wallInset` px from a wall, at least `minRange` px from its
  -- target (best of `spotSamples` random spots: the closest valid one), aims
  -- a thin red line for `aimTime` s (locked the last `lockTime` s) and fires
  -- one fast shot, then moves to a new spot; `fireInterval` s from a shot to
  -- the next aim. A target closer than `fleeRange` cancels the aim: it runs.
  sniper   = { hp = 2, speed = 60, size = 12, radius = 6, points = 300, color = "sniper", contactDamage = true,
               name = "SNIPER", wallInset = 30, minRange = 180, fleeRange = 100, spotSamples = 10,
               aimTime = 1.0, lockTime = 0.25, fireInterval = 2.0,
               bulletSpeed = 450, bulletLife = 2.0, bulletRadius = 3,
               reach = 1000, lineAlpha = 0.45, lineWidth = 1 },
  -- Keeps `keepDistance` px, and every `launchInterval` s (hatches blinking
  -- for the last `hatchTime` s) launches up to `launchCount` `spawn` drones
  -- out of its sides (`hatchOffset` px, at `launchSpeed`), `maxDrones` alive
  -- at most. Its drones blow up with it (no points).
  carrier  = { hp = 12, speed = 25, size = 26, radius = 12, points = 800, color = "carrier", contactDamage = true,
               push = 3.0, hpBar = true, name = "PORTA-NAVES", keepDistance = 140,
               launchInterval = 4.0, hatchTime = 0.4, launchCount = 2, maxDrones = 4,
               launchSpeed = 90, hatchOffset = 13, spawn = "scout" },
  -- Carrier drone: flies out harmless for `harmlessTime` s, then homes in,
  -- turning at most `turnRate` rad/s. Outside the wave quota.
  scout    = { hp = 1, speed = 100, size = 8, radius = 4, points = 50, color = "carrier", contactDamage = true,
               harmlessTime = 0.3, turnRate = math.rad(150) },
}

-- Spacing between enemies (steering in src/entities/enemy.lua, hard overlap
-- fix in src/systems/combat.lua). Each enemy's "space" is half its drawn
-- sprite size (Config.ART.size): sprites never overlap, and enemies steer to
-- keep `gap` px more between them.
Config.ENEMY_SPACING = {
  gap = 4,           -- px kept between sprites (soft: steered around)
  steer = 1.6,       -- weight of the avoidance against the chase direction
  bossFrac = 0.45,   -- the boss as an obstacle: radius = this * its drawn size
}
-- Largest enemy space: neighbor queries reach this far (computed once).
do
  local m = 0
  for kind, def in pairs(Config.ENEMIES) do
    local s = (Config.ART.size[kind] or def.size) * 0.5
    if s > m then m = s end
  end
  Config.ENEMY_SPACING.maxSpace = m
end

-- With no live player (respawn wait, both dead in 2P), enemies wander
-- instead of standing still: a new heading every turnMin..turnMax s, eased
-- in, pointing back inside near the walls.
Config.ENEMY_WANDER = {
  speedMul = 0.6,
  turnMin = 1.0, turnMax = 2.5,   -- s between new headings
  maxTurn = math.rad(90),         -- how far a new heading may swing
  turnRate = math.rad(140),       -- rad/s easing toward it
  wallMargin = 40,                -- px: closer than this, the new heading points inward
  inwardSpread = math.rad(45),    -- random swing around the inward heading
}

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
  debutCount = 3,             -- a new type's debut wave: its first batch brings this many
  -- The curve (see the functions below; `love . --curve` prints it). It
  -- grows by density and mix, not by length: the total per wave is linear.
  quotaBase = 12, quotaPerWave = 4,           -- enemies per wave
  aliveBase = 10, alivePerWave = 1.6,         -- alive at once
  intervalBase = 0.95, intervalPerWave = 0.03, intervalMin = 0.25,   -- s between batches
  coopQuota = 1.5,            -- 2 players: x the total ...
  coopAlive = 1.35,           -- ... and x the alive cap (also the boss adds)
}

local function coop(players, mul)
  return (players or 1) >= 2 and mul or 1
end

function Config.waveQuota(w, players)
  local W = Config.WAVE
  return math.floor((W.quotaBase + W.quotaPerWave * w) * coop(players, W.coopQuota))
end

function Config.waveMaxAlive(w, players)
  local W = Config.WAVE
  return math.min(Config.MAX_ENEMIES,
    math.floor((W.aliveBase + W.alivePerWave * w) * coop(players, W.coopAlive)))
end

function Config.waveSpawnInterval(w)
  local W = Config.WAVE
  return math.max(W.intervalMin, W.intervalBase - W.intervalPerWave * w)
end

-- Elites (from ELITE.from on): any enemy out of a door may come out elite,
-- with more HP, a bit faster, worth more and outlined in gold. The chance
-- grows perWave per wave up to `max`. The endless lever once every type is in.
Config.ELITE = {
  from = 20, perWave = 0.015, max = 0.30,
  hpMul = 2, speedMul = 1.15, pointsMul = 2,
  color = { 1.00, 0.82, 0.30, 1 },
  outline = 5,       -- px the gold outline sprite is drawn bigger
  ring = 0.7,        -- gold ring around it (radius x its drawn size), 1.5px
  alpha = 0.55,      -- outline alpha (pulses around it)
  pulse = 4,         -- Hz
  glow = 0.25,       -- halo in the glow layer
}

function Config.eliteChance(w)
  local E = Config.ELITE
  if w < E.from then return 0 end
  return math.min(E.max, (w - E.from + 1) * E.perWave)
end

-- Quantos inimigos saem por porta de cada vez. Cresce com a wave, senão o
-- telégrafo (0.4s por lote) limitaria a pressão a ~3 inimigos/s.
function Config.waveBatch(w)
  return Config.WAVE.batchMin, math.min(8, Config.WAVE.batchMax + math.floor(w / 6))
end

-- ---------------------------------------------------------------------------
-- Boss (src/entities/boss.lua): one every `every` waves.
-- ---------------------------------------------------------------------------
-- Values that scale per boss are { base = , perBoss = , min = , max = }:
-- boss n (n = 1 at wave 10, 2 at wave 20...) gets base + perBoss * (n - 1),
-- clamped to min/max when given. Read them with Config.bossValue(spec, n).
-- Counts (burst count, fan, drops...) are floored.
Config.BOSS = {
  every = 10,
  size = 130,                 -- px, longest side of the sprite (~40% of the arena height)
  radiusFrac = 0.36,          -- hitbox radius as a fraction of `size` (check with F1)
  growPerCycle = 0.12,        -- extra size each time the variant list starts over
  warnTime = 2.0,             -- s of "ALERTA" banner before the entrance
  enterSpeed = 55,            -- px/s while sliding in (invulnerable, holding fire)
  -- Energy shield while sliding in: player shots die on it (with a ripple
  -- where they hit) and it pops when the fight starts. `radiusFrac` of the
  -- boss size; color = variant color lightened by `lighten`. `hexScale` =
  -- hex cells per shield radius. `popTime`/`popGrow`: the burst at the end.
  shield = {
    radiusFrac = 0.55, fadeIn = 0.3, lighten = 0.35,
    rimAlpha = 0.6, hexAlpha = 0.35, fillAlpha = 0.06, hexScale = 7,
    hitLife = 0.45, popTime = 0.25, popGrow = 0.35, breakShake = 3, sparks = 14,
  },
  turnRate = 2.0,             -- how fast the sprite turns toward its target (visual)
  margin = 24,                -- px kept between the hull and the walls while roaming
  pauseMin = 0.6,             -- s it stops at each roaming point
  pauseMax = 1.6,
  hp     = { base = 300, perBoss = 260 },
  coopHp = 1.6,               -- 2 players: x the boss HP
  speed  = { base = 22, perBoss = 3, max = 40 },          -- px/s while roaming
  points = { base = 5000, perBoss = 2500 },                -- split by each player's damage
  drops  = { base = 2, perBoss = 0.5, max = 4 },           -- power-ups out of the wreck
  -- Aimed bursts: every `interval` s, `count` volleys `gap` s apart, each
  -- volley a fan of `fan` shots spread over `fanAngle`.
  burst = {
    interval    = { base = 2.4, perBoss = -0.25, min = 1.1 },
    count       = { base = 3, perBoss = 1, max = 8 },
    gap         = 0.14,
    fan         = { base = 1, perBoss = 1, max = 5 },
    fanAngle    = math.rad(28),
    bulletSpeed = { base = 140, perBoss = 12, max = 220 },
    bulletLife  = 4.0,
  },
  -- Homing missile: chases its target for `homingTime`, then sputters for
  -- `failTime` (slowing down to failSpeedMul of its speed) and blows up
  -- harmlessly. Deadly on contact until then; `hp` hits shoot it down.
  missile = {
    interval   = { base = 6.0, perBoss = -0.6, min = 2.8 },
    maxAlive   = { base = 1, perBoss = 1, max = 4 },
    hp         = 3,
    points     = 100,         -- for shooting one down
    speed      = 95,
    turn       = math.rad(120),   -- rad/s while homing
    homingTime = 3.5,
    failTime   = 1.2,
    failSpeedMul = 0.35,
    radius     = 5,
  },
  -- Rage below `below` of its HP: fires and launches faster, roams faster
  -- and pulses red.
  rage = { below = 0.4, fireMul = 1.5, missileMul = 1.6, speedMul = 1.35, pulseRate = 3 },
  -- Normal enemies through the doors during the fight (not before boss
  -- `fromBoss`), using that wave's usual mix, with no quota.
  adds = {
    fromBoss = 2,
    maxAlive = { base = 4, perBoss = 2, max = 24 },
    interval = { base = 2.6, perBoss = -0.25, min = 0.8 },
  },
  -- Death: `time` s of small blasts over the hull, then the big one.
  death = { time = 1.6, blastEvery = 0.11, shake = 10, hitStop = 0.12, pulse = 0.9 },
  -- Engine flames (the player's flame sprites, additive): one per nozzle of
  -- the variant, in the variant color with a white core. Length factor:
  -- `idle` while stopped, `cruise` at roaming speed, `enter` while sliding
  -- in; eased at `ease`/s. Rage makes them longer and redder; while dying
  -- they sputter and shrink out. `lighten` mixes the outer flame toward
  -- white: dark colors (purple, red) barely light up when drawn additively.
  engine = { idle = 0.7, cruise = 1.0, enter = 1.4, ease = 4, lighten = 0.35,
             rageMul = 1.3, rageTint = 0.6, coreScale = 0.55, coreAlpha = 0.9 },
  -- Boss n uses entry ((n - 1) % #variants) + 1. Names show in the alert
  -- banner (big font: keep them unaccented) and on the HUD bar. `engines`:
  -- nozzles as { u, v, s }: u, v = spot on the sprite as authored (0..1 from
  -- its left/top; the ships point down, so the exhausts are near v = 0) and
  -- s = flame size as a fraction of the boss size.
  variants = {
    { name = "DESTRUIDOR", sprite = "boss1", color = { 0.95, 0.25, 0.25 },
      engines = { { 0.28, 0.12, 0.30 }, { 0.72, 0.12, 0.30 } } },
    { name = "CEIFADOR",   sprite = "boss2", color = { 0.70, 0.35, 1.00 },
      engines = { { 0.24, 0.06, 0.28 }, { 0.76, 0.06, 0.28 } } },
    { name = "DEVORADOR",  sprite = "boss3", color = { 0.25, 0.95, 0.55 },
      engines = { { 0.50, 0.04, 0.42 } } },
    { name = "COLOSSO",    sprite = "boss4", color = { 1.00, 0.60, 0.15 },
      engines = { { 0.32, 0.06, 0.30 }, { 0.66, 0.06, 0.30 } } },
    { name = "SENTINELA",  sprite = "boss5", color = { 0.30, 0.75, 1.00 },
      engines = { { 0.50, 0.04, 0.32 }, { 0.20, 0.06, 0.18 }, { 0.80, 0.06, 0.18 } } },
  },
}

function Config.bossValue(spec, n)
  local v = spec.base + (spec.perBoss or 0) * (n - 1)
  if spec.min and v < spec.min then v = spec.min end
  if spec.max and v > spec.max then v = spec.max end
  return v
end

-- Pesos do mix de inimigos por wave; tipo só entra a partir de `from`.
-- Each weight ramps up from `from` and levels off at `max` (the grunt goes
-- down to its `min` instead: it is the filler that keeps the rhythm, never
-- below ~15%).
Config.ENEMY_MIX = {
  { type = "grunt",    from = 1,  base = 100, perWave = -3,  min = 45 },
  { type = "runner",   from = 1,  base = 5,   perWave = 6,   min = 0, max = 60 },
  { type = "shooter",  from = 2,  base = 4,   perWave = 5,   min = 0, max = 45 },
  { type = "tank",     from = 4,  base = -4,  perWave = 4,   min = 0, max = 35 },
  -- New types (`debut`: their first wave shows "NOVO: <name>" and opens with
  -- WAVE.debutCount of them).
  { type = "kamikaze", from = 7,  base = -16, perWave = 4,   min = 0, max = 35, debut = true },
  { type = "divisor",  from = 9,  base = -24, perWave = 4,   min = 0, max = 30, debut = true },
  { type = "sniper",   from = 12, base = -30, perWave = 3.5, min = 0, max = 20, debut = true },
  { type = "carrier",  from = 15, base = -40, perWave = 3.5, min = 0, max = 15, debut = true },
}

-- Weight of mix entry `m` at wave `w` (0 before it comes in).
function Config.mixWeight(m, w)
  if w < m.from then return 0 end
  local v = m.base + m.perWave * w
  if m.min and v < m.min then v = m.min end
  if m.max and v > m.max then v = m.max end
  return math.max(0, v)
end

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
  dropChance = 0.10,
  pickupRadius = 9,           -- drawn size lives in Config.ART.size.pickup
  pickupLife = 10,
  blinkAt = 3,                -- começa a piscar nos últimos N segundos
  -- The blink (a white ring around it, the pickup never disappears) speeds up from
  -- blinkRateMin to blinkRateMax Hz as its life runs out.
  blinkRateMin = 3,
  blinkRateMax = 10,
  -- Wave-end drop: of `dropSamples` random spots (at least dropMargin px
  -- from the walls), the one farthest from the players and respawn markers.
  dropSamples = 12,
  dropMargin = 40,
}

-- Per power-up numbers (src/systems/powerups.lua holds names, colors and the
-- logic). `duration` in seconds, `weight` = share in the random drop.
Config.POWERUPS = {
  spread   = { duration = 12, weight = 20 },
  rapid    = { duration = 12, weight = 20, fireMul = 2 },
  missiles = { duration = 12, weight = 15 },        -- damage: Config.WEAPON.missileDamage
  boots    = { duration = 12, weight = 18, speedMul = 1.4 },
  life     = { weight = 6 },
  -- Absorbs one hit, then pops: pushes enemies within pushRadius out by
  -- `push` px and grants `invuln` s. Lasts until used or `duration`.
  bubble   = { duration = 20, weight = 12, pushRadius = 50, push = 28, invuln = 1.0 },
  -- Instant shockwave around the player: damage within `radius`, enemy
  -- shots in it are erased.
  nova     = { weight = 5, radius = 130, damage = 5 },
  -- Orbiting drone that auto-aims at the nearest visible enemy.
  -- Its shots are energy pellets (white core `shotCore`, glow `shotGlow` in
  -- the player color) so they don't read as the ship's; a `barrel` px stub
  -- points at the target and flashes for `flashTime` on each shot.
  drone    = { duration = 12, weight = 12, fireRate = 10, damage = 1, distance = 22, spin = math.rad(160),
               shotCore = 1.6, shotGlow = 4.5, barrel = 5, flashTime = 0.06 },
  -- While active, shots are drawn `shotScale` bigger with a `glowMul` stronger
  -- glow in `color` (the badge color), hits spark in it, and the ship's
  -- outline pulses in it at `auraRate` Hz.
  damage   = { duration = 10, weight = 12, mul = 2, color = { 1.00, 0.40, 0.30, 1 },
               shotScale = 1.4, glowMul = 1.5, auraRate = 6 },
}

-- ---------------------------------------------------------------------------
-- Permanent upgrades (src/systems/upgrades.lua holds names, texts and the
-- offer rules; src/states/upgrade.lua the picking screen). One pick after
-- every `every`-th wave is cleared (after the boss on boss waves), kept for
-- the whole match, applied under the temporary power-ups.
--   openDelay   -- s into the breather before the screen opens
--   acceptDelay -- s before START counts (ignores a START already held)
--   pickPitch   -- the pick sound is pickup_life at this pitch
-- Per upgrade: `mul` per level (multiplied), `max` levels. Uniques have 3
-- levels (base, +, ++); their per-level numbers are lists.
-- ---------------------------------------------------------------------------
Config.UPGRADES = {
  every = 5,
  openDelay = 0.6,
  acceptDelay = 0.4,
  pickPitch = 0.85,
  statColor = { 0.55, 0.80, 1.00, 1 },     -- light blue: stats
  uniqueColor = { 1.00, 0.80, 0.30, 1 },   -- gold: uniques
  cadence  = { mul = 1.2,  max = 3 },      -- fire rate
  motor    = { mul = 1.12, max = 3 },      -- move speed
  thruster = { mul = 0.8,  max = 2 },      -- dash cooldown
  duration = { mul = 1.35, max = 2 },      -- temporary power-up time
  hull     = { max = 2 },                  -- +1 life now and +1 max life
  magnet   = { max = 1, radius = 50, pull = 180 },   -- px, px/s
  pierce   = { 1, 2, math.huge },          -- extra enemies a shot passes through
  rear     = { rates = { 0.5, 1, 1 }, fan = { 1, 1, 3 }, fanAngle = math.rad(30) },
  loyal    = { rates = { 0.5, 1, 1 }, counts = { 1, 1, 2 } },   -- permanent drones
  -- LÂMINA: dash damage to each enemy it passes through (once per dash);
  -- at the top level a blade kill recharges the dash.
  blade    = { damage = { 3, 6, 6 }, resetOnKill = { false, false, true } },
  -- RECARGA: a free BOLHA every `interval` s without one; at the top level
  -- the bubble pops with a NOVA.
  recharge = { interval = { 30, 20, 20 }, popNova = { false, false, true } },
  -- RICOCHETE: player shots bounce off the walls; at the top level a shot
  -- that bounced homes in (nearest enemy within `range`, `turn` rad/s).
  ricochet = { bounces = { 1, 2, 2 }, homing = { false, false, true },
               turn = math.rad(150), range = 160,
               afterLife = 0.6 },   -- s a shot may live on after a bounce (keeps the pool sane)
  -- CHOQUE: a mini-NOVA when the dash ends (and when it starts, top level).
  shock    = { radius = { 50, 70, 70 }, damage = { 2, 3, 3 }, onStart = { false, false, true },
               volume = 0.45, pitch = 1.5 },
}

-- Respawn (with lives left; not the comeback at wave end after running out).
-- `markerDelay` s after the death, a marker shows up where the ship died: it
-- comes back there, unless the player steers the marker with the move stick
-- during the countdown. On respawn: a salvo of homing missiles (count =
-- base + floor(wave / everyWaves), up to max), each to a different nearby
-- enemy, plus a weapon power-up dropped dropDistMin..dropDistMax px away.
-- The comeback at wave end (after running out of lives) uses the safest
-- spot instead: of `samples` random spots, the farthest from any threat.
Config.RESPAWN = {
  lastLifeBubble = true,      -- coming back on the last life grants the BOLHA
  markerDelay = 1.0,          -- s after the death before the marker shows (and moves)
  markerSpeed = 260,          -- px/s when the player steers it
  samples = 16,
  margin = 40,                -- px from the walls for candidate spots
  dropDistMin = 50,
  dropDistMax = 70,
  salvo = { base = 4, everyWaves = 10, max = 10, speed = 260, turn = math.rad(300),
            life = 2.5, damage = 6, blastRadius = 40, blastDamage = 4 },
}

-- ---------------------------------------------------------------------------
-- Som
-- ---------------------------------------------------------------------------
-- Dois tipos de arquivo, ambos em assets/sfx/:
--   * Kenney (Sci-Fi Sounds, CC0): `src` + `variants` apontam para
--     "<src>_000.ogg".."<src>_00N.ogg"; cada disparo sorteia uma variação
--     diferente da anterior. Só os arquivos usados ficam em assets/sfx/kenney/
--     (o pacote completo em assets/sfx/Audio/ fica fora do build).
--   * sfxr: "<id>.wav" (ou .ogg), gerado por tools/gen_sfx.py. É o som dos
--     ids sem `src` e o fallback dos que têm, se nenhuma variação carregar.
-- Som sem arquivo é ignorado em silêncio, então dá para ir adicionando aos poucos.
--   vol      -- volume base (0..1), multiplicado por AUDIO.master
--   voices   -- cópias pré-carregadas: quantas instâncias tocam ao mesmo tempo.
--               Com variações, é o total, repartido entre elas (mínimo 1 cada)
--   pitch    -- pitch base (1 = original), antes da variação aleatória
--   pitchVar -- variação aleatória de pitch (0.05 = +-5%): evita repetição robótica
--   minGap   -- intervalo mínimo entre dois disparos do mesmo som (s)
Config.AUDIO = {
  master = 0.8,
  dir = "assets/sfx/",
}

Config.SFX = {
  -- Tiros (tocam muito: volume baixo, várias vozes, throttle). O tiro inimigo
  -- usa o mesmo laser do spread, bem mais grave, para soar como ameaça.
  shot          = { src = "kenney/laserSmall", variants = 5,
                    vol = 0.26, voices = 6, pitchVar = 0.06, minGap = 0.05 },
  shot_spread   = { src = "kenney/laserRetro", variants = 5,
                    vol = 0.25, voices = 6, pitchVar = 0.06, minGap = 0.05 },
  shot_missile  = { src = "kenney/laserLarge", variants = 5,
                    vol = 0.20, voices = 5, pitch = 0.9, pitchVar = 0.05, minGap = 0.06 },
  shot_enemy    = { src = "kenney/laserRetro", variants = 5,
                    vol = 0.18, voices = 4, pitch = 0.7, pitchVar = 0.08, minGap = 0.08 },
  -- Impacto e morte
  enemy_hit     = { src = "kenney/impactMetal", variants = 5,
                    vol = 0.16, voices = 4, pitchVar = 0.10, minGap = 0.04 },
  enemy_die     = { src = "kenney/explosionCrunch", variants = 5,
                    vol = 0.32, voices = 6, pitchVar = 0.12, minGap = 0.03 },
  tank_die      = { src = "kenney/lowFrequency_explosion", variants = 2,
                    vol = 0.55, voices = 2, pitchVar = 0.05, minGap = 0.10 },
  player_die    = { src = "kenney/lowFrequency_explosion", variants = 2,
                    vol = 0.60, voices = 2, pitch = 0.8, pitchVar = 0.00, minGap = 0.10 },
  player_spawn  = { src = "kenney/forceField", variants = 5,
                    vol = 0.30, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  -- Power-ups
  pickup        = { vol = 0.60, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  pickup_life   = { vol = 0.70, voices = 1, pitchVar = 0.00, minGap = 0.10 },
  powerup_end   = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  bubble_pop    = { src = "kenney/forceField", variants = 5,
                    vol = 0.45, voices = 2, pitch = 1.3, pitchVar = 0.05, minGap = 0.10 },
  nova          = { src = "kenney/lowFrequency_explosion", variants = 2,
                    vol = 0.70, voices = 1, pitch = 1.2, pitchVar = 0.00, minGap = 0.20 },
  salvo_launch  = { src = "kenney/laserLarge", variants = 5,
                    vol = 0.40, voices = 2, pitch = 0.8, pitchVar = 0.04, minGap = 0.10 },
  salvo_blast   = { src = "kenney/explosionCrunch", variants = 5,
                    vol = 0.30, voices = 4, pitch = 0.9, pitchVar = 0.10, minGap = 0.04 },
  drone_shot    = { src = "kenney/laserSmall", variants = 5,
                    vol = 0.14, voices = 3, pitch = 1.4, pitchVar = 0.06, minGap = 0.05 },
  -- Dash: the force field pitched way up, a short whoosh.
  dash          = { src = "kenney/forceField", variants = 5,
                    vol = 0.30, voices = 2, pitch = 2.2, pitchVar = 0.06, minGap = 0.05 },
  -- New enemies: a low charge-up hum while the kamikaze aims, its launch,
  -- the clang when it hits a wall, and the divisor cracking open.
  kamikaze_aim  = { src = "kenney/laserRetro", variants = 5,
                    vol = 0.20, voices = 3, pitch = 0.45, pitchVar = 0.05, minGap = 0.10 },
  kamikaze_charge = { src = "kenney/laserLarge", variants = 5,
                    vol = 0.28, voices = 3, pitch = 0.7, pitchVar = 0.06, minGap = 0.08 },
  kamikaze_stun = { src = "kenney/impactMetal", variants = 5,
                    vol = 0.30, voices = 3, pitch = 0.8, pitchVar = 0.08, minGap = 0.08 },
  divisor_split = { src = "kenney/impactMetal", variants = 5,
                    vol = 0.30, voices = 3, pitch = 1.4, pitchVar = 0.08, minGap = 0.06 },
  -- Sniper: a thin hum while aiming, a sharp crack when it fires. Carrier:
  -- a deep clunk when its hatches open.
  sniper_aim    = { src = "kenney/laserSmall", variants = 5,
                    vol = 0.18, voices = 3, pitch = 0.6, pitchVar = 0.05, minGap = 0.10 },
  sniper_shot   = { src = "kenney/laserLarge", variants = 5,
                    vol = 0.30, voices = 3, pitch = 1.5, pitchVar = 0.05, minGap = 0.06 },
  carrier_launch = { src = "kenney/doorOpen", variants = 3,
                    vol = 0.30, voices = 2, pitch = 0.6, pitchVar = 0.05, minGap = 0.10 },
  -- Waves e combo
  door_warn     = { src = "kenney/doorOpen", variants = 3,
                    vol = 0.15, voices = 4, pitchVar = 0.04, minGap = 0.12 },
  wave_start    = { vol = 0.60, voices = 1, pitchVar = 0.00, minGap = 0.50 },
  wave_clear    = { vol = 0.70, voices = 1, pitchVar = 0.00, minGap = 0.50 },
  combo_up      = { vol = 0.55, voices = 2, pitchVar = 0.00, minGap = 0.10 },
  combo_lost    = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.20 },
  game_over     = { vol = 0.80, voices = 1, pitchVar = 0.00, minGap = 1.00 },
  -- Interface
  menu_move     = { vol = 0.45, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  menu_confirm  = { vol = 0.55, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  menu_cancel   = { vol = 0.50, voices = 2, pitchVar = 0.00, minGap = 0.05 },
  -- Boss: the same Kenney files, pitched down to sound heavier.
  boss_alarm    = { src = "kenney/doorOpen", variants = 3,
                    vol = 0.45, voices = 2, pitch = 0.5, pitchVar = 0.00, minGap = 0.30 },
  boss_shot     = { src = "kenney/laserRetro", variants = 5,
                    vol = 0.22, voices = 4, pitch = 0.5, pitchVar = 0.06, minGap = 0.06 },
  boss_missile  = { src = "kenney/laserLarge", variants = 5,
                    vol = 0.35, voices = 2, pitch = 0.55, pitchVar = 0.04, minGap = 0.20 },
  boss_hit      = { src = "kenney/impactMetal", variants = 5,
                    vol = 0.12, voices = 3, pitch = 0.6, pitchVar = 0.08, minGap = 0.07 },
  missile_fail  = { src = "kenney/explosionCrunch", variants = 5,
                    vol = 0.30, voices = 3, pitch = 0.8, pitchVar = 0.08, minGap = 0.05 },
  boss_blast    = { src = "kenney/explosionCrunch", variants = 5,
                    vol = 0.35, voices = 4, pitch = 0.7, pitchVar = 0.12, minGap = 0.06 },
  boss_die      = { src = "kenney/lowFrequency_explosion", variants = 2,
                    vol = 0.85, voices = 1, pitch = 0.6, pitchVar = 0.00, minGap = 0.50 },
  -- Boss entry shield: a high metallic tink per blocked shot, a deep force
  -- field burst when it pops.
  shield_hit    = { src = "kenney/impactMetal", variants = 5,
                    vol = 0.12, voices = 3, pitch = 1.6, pitchVar = 0.10, minGap = 0.06 },
  shield_break  = { src = "kenney/forceField", variants = 5,
                    vol = 0.60, voices = 1, pitch = 0.6, pitchVar = 0.00, minGap = 0.50 },
  -- Screen transition wipe: a soft, short whoosh.
  transition    = { src = "kenney/forceField", variants = 5,
                    vol = 0.20, voices = 1, pitch = 1.8, pitchVar = 0.05, minGap = 0.30 },
}

-- ---------------------------------------------------------------------------
-- Música
-- ---------------------------------------------------------------------------
-- Files in assets/music/<name>.ogg (or .wav). Each screen asks for a ROLE;
-- a role is one looped track ({ file = ... }) or a gapless playlist
-- ({ playlist = { ... } }, a -> b -> c -> a ...). Optional per role:
-- `gain` (0..1, evens out loudness between tracks) and `fadeIn` (s, instead
-- of fadeTime). A role always restarts from its beginning once faded out.
Config.MUSIC = {
  dir = "assets/music/",
  volume = 0.45,          -- below the SFX, so shots/explosions stand out
  duck = 0.3,             -- volume fraction while paused
  fadeTime = 0.6,         -- default fade in/out and crossfade (s)
  gameOverDelay = 2.5,    -- silence on game over before its music comes in
  tracks = {
    menu = { file = "sunburn" },                     -- lobby, briefing
    game = { playlist = { "cloak-of-darkness-1",     -- regular waves
                          "cloak-of-darkness-2",
                          "cloak-of-darkness-3" } },
    -- Starts loud: comes in slowly once the boss actually starts fighting.
    boss = { file = "never-miss", fadeIn = 3.0 },
    gameover = { file = "crushing-it" },
  },
}

-- ---------------------------------------------------------------------------
-- Touch controls (src/touch.lua): floating sticks in the arena (left half
-- moves, right half aims; the base follows a finger dragged past
-- stickRadius), a tap anywhere else is START. Logical px.
-- ---------------------------------------------------------------------------
Config.TOUCH = {
  stickRadius = 34,
  knobRadius = 12,
  deadzone = 0.12,
  ghostRadius = 28,    -- faint hint circles in the bottom corners
  ghostAlpha = 0.12,
  ghostInset = 56,     -- their distance from the corners
  buttonPad = 8,       -- extra hit margin around on-screen buttons
  pauseSize = 18,      -- pause button in the HUD
  dashRadius = 18,     -- DASH button, above the aim ghost
  dashLift = 62,       -- its center this many px above the aim ghost's
}

-- ---------------------------------------------------------------------------
-- Game over sequence: when the last player runs out, the arena keeps running
-- (doors closed) in slow motion for a moment, then GAME OVER + the score
-- show over it, and START goes to the results screen. Times in real seconds
-- from the last death.
-- ---------------------------------------------------------------------------
Config.GAME_OVER = {
  slowMo = 0.35,       -- time scale right after the last death
  slowHold = 0.4,      -- s at slowMo, then
  slowEase = 0.5,      -- s easing back to normal speed
  textDelay = 1.0,     -- s before GAME OVER shows (and its jingle plays)
  fadeIn = 0.4,        -- s for the text and the dimming to fade in
  dim = 0.6,           -- arena darkening behind the text (alpha)
  acceptDelay = 0.6,   -- s after the text before START works
}

-- ---------------------------------------------------------------------------
-- Juice
-- ---------------------------------------------------------------------------
Config.JUICE = {
  shakeScale = 1,          -- global multiplier for every screen shake (0 = off)
  shakeEnemyDeath = 0.8,
  shakePlayerDeath = 7.0,  -- forced: ignores fatigue
  shakeTankDeath = 2.0,
  shakeDecay = 12,
  -- Shake fatigue: back-to-back shakes get weaker, so a chain of kills in a
  -- dense wave doesn't keep the screen trembling. Each shake adds
  -- `gain * magnitude` (capped at 1) and plays at max(minMul, 1 - fatigue)
  -- of its strength; fatigue drains `recover` per second. Player and boss
  -- deaths are forced and skip it.
  shakeFatigue = { gain = 0.15, recover = 1.0, minMul = 0.25 },
  hitStopTank = 0.05,
  hitStopCooldown = 0.4,   -- s: at most one tank hit-stop per window
  -- Explosions (src/entities/particle.lua). One preset per kind of blast;
  -- every particle comes from the same pool (size in Config.FX.particles).
  --   flash     -- px, white core flash (0 = none)
  --   fire      -- additive puffs (white -> hot -> the blast color), fireSize px
  --   sparks    -- additive streaks, sparkSize px wide
  --   smoke     -- dark puffs under the enemies, smokeSize px
  --   ring      -- px, thin shock ring (nil = none)
  -- Emitted in that order, so a nearly full pool loses smoke, not fire.
  explosions = {
    small     = { flash = 20,  fire = 3,  fireSize = 14, sparks = 6,  sparkSize = 2.0, smoke = 2, smokeSize = 16 },
    tank      = { flash = 36,  fire = 6,  fireSize = 22, sparks = 12, sparkSize = 2.5, smoke = 4, smokeSize = 26, ring = 46 },
    player    = { flash = 46,  fire = 7,  fireSize = 24, sparks = 16, sparkSize = 2.5, smoke = 5, smokeSize = 28, ring = 60 },
    bossBlast = { flash = 30,  fire = 2,  fireSize = 22, sparks = 4,  sparkSize = 2.5, smoke = 1, smokeSize = 24 },
    boss      = { flash = 100, fire = 12, fireSize = 50, sparks = 26, sparkSize = 3.0, smoke = 8, smokeSize = 52, ring = 160 },
    missile   = { flash = 20,  fire = 2,  fireSize = 12, sparks = 5,  sparkSize = 2.0, smoke = 2, smokeSize = 14 },
    salvo     = { flash = 26,  fire = 3,  fireSize = 18, sparks = 6,  sparkSize = 2.0, smoke = 2, smokeSize = 18 },
  },
  -- Staged blasts: secondary `small` pops around the big ones, `delayMin` to
  -- `delayMax` s later (game time), within `radius` px.
  stages = {
    player = { count = 3, delayMin = 0.10, delayMax = 0.30, radius = 12 },
    boss   = { count = 3, delayMin = 0.12, delayMax = 0.40, radius = 40 },
  },
  -- Color over life (0..1 of the particle's life): white -> `hot` until
  -- `hotEnd`, `hot` -> the blast color until `colorEnd`, then the color.
  ramp = { hot = { 1.0, 0.85, 0.45 }, hotEnd = 0.08, colorEnd = 0.40 },
  spark  = { speedMin = 70, speedMax = 240, lifeMin = 0.20, lifeMax = 0.45, drag = 3.5,
             stretch = 0.065, minLen = 2 },   -- streak length = speed * stretch (s)
  fire   = { speedMin = 8, speedMax = 40, lifeMin = 0.22, lifeMax = 0.40, drag = 3.0,
             grow = 0.9, alpha = 0.6, spin = 2.0 },
  flashAlpha = 0.75,
  smoke  = { speedMin = 6, speedMax = 30, lifeMin = 0.45, lifeMax = 0.75, drag = 1.5,
             grow = 0.7, alpha = 0.55, darken = 0.28, spin = 1.0 },
  flashLife = 0.08,
  -- Debris: the sprite's 4 quadrants fly apart (tank, player, boss).
  debris = { speedMin = 30, speedMax = 80, lifeMin = 0.50, lifeMax = 0.85, drag = 1.5, spin = 6 },
  -- Impact sparks on a hit that doesn't kill: `count` streaks bouncing back
  -- against the shot, within +-`spread` rad.
  impact = { count = 2, spread = math.rad(45), speedMin = 70, speedMax = 150,
             lifeMin = 0.10, lifeMax = 0.20, size = 1.5 },
  -- Low-priority particles only spawn below this share of the pool, so they
  -- never starve the explosions.
  poolShare = { smoke = 0.8, debris = 0.8, impact = 0.6 },
  -- Missile smoke trail (same pool rule, trailPoolShare).
  trailInterval = 0.07,
  trailLife = 0.3,
  trailSize = 6,
  trailAlpha = 0.85,
  trailPoolShare = 0.6,
  particleSize = 4,           -- default spark width for Particle.burst
}

-- ---------------------------------------------------------------------------
-- Visual effects (src/post.lua)
-- ---------------------------------------------------------------------------
Config.FX = {
  -- "high" | "low" | "off" | "auto" (low in the browser, high elsewhere).
  -- Overridden by --fx on the command line. "off" keeps the glow layer but
  -- skips the blur (the same path used when the shader fails to compile).
  quality = "auto",
  glow = {
    -- Glow canvas size as a fraction of the 640x360 logical screen. "wide"
    -- adds a second, half-size blurred level for a broad halo.
    high = { scale = 0.5,  wide = true },
    low  = { scale = 0.25, wide = false },
    spread = 1.0,          -- blur radius multiplier (texels per tap step)
    intensity = 1.6,       -- tight level gain
    wideIntensity = 1.0,   -- wide level gain
  },
  -- Particle pool size per quality ("off" uses low). Sized for an old i5
  -- (3rd gen): the CPU, not the GPU, is the limit.
  particles = { high = 320, low = 160 },
  -- Depth. Ships and pickups cast a soft drop shadow down-right (light from
  -- the top left): offset = `offset` x the sprite size (at least `minOffset`
  -- px) along (dirX, dirY); `alpha` = how dark a fully covered spot gets.
  shadow = { alpha = 0.55, dirX = 0.6, dirY = 0.8, offset = 0.2, minOffset = 3 },
  -- Muzzle flash: a hot core + a halo in the player's color at the ship's
  -- nose on every shot (lasts PLAYER.muzzleTime); the boss gets a pink one
  -- on each volley. Sizes are radii in px; `nose` = fraction of the ship
  -- size ahead of its center.
  muzzle = { size = 6, coreSize = 2.5, nose = 0.55, bossTime = 0.08, bossSize = 12 },
  -- Motion trails.
  --   shot*   -- smear behind player shots (px long / wide)
  --   ribbon* -- engine ribbon behind the players' ships: a point every
  --              `ribbonEvery` s, gone after `ribbonLife` s
  --   echo*   -- runner afterimages: `echoes` copies sampled every
  --              `echoEvery` s, the nearest at `echoAlpha`
  trail = {
    shot = 10, shotWidth = 2.5,
    ribbonPoints = 14, ribbonEvery = 0.02, ribbonLife = 0.25, ribbonWidth = 6, ribbonAlpha = 0.55,
    echoes = 3, echoEvery = 0.035, echoAlpha = 0.35,
  },
  -- Dissolve (src/shaders.lua): things appearing and vanishing. `edgeWidth`
  -- = glowing band at the dissolve front (0..1 of the noise range);
  -- `noiseScale` = noise cells across a sprite.
  dissolve = { spawnTime = 0.3, edgeWidth = 0.12, noiseScale = 7, pickupVanish = 0.3 },
  -- Door portal during the spawn telegraph: an ellipse along the wall that
  -- opens as the lamp blinks, and a flash when the batch comes out. Sizes
  -- in px (`length` along the wall, `depth` into the arena).
  portal = { length = 42, depth = 16, alpha = 0.4, flashTime = 0.15, flashGrow = 0.6 },
  -- Pickups on the floor:
  --   sheen*  -- a diagonal band of light crossing the badge every
  --              `sheenEvery` s (each pickup on its own phase), in `sheenTime` s
  --   pop*    -- dropped: scale 0 -> popPeak -> 1 over `popTime` s
  --   *Ring   -- ring radius (px) on drop / on pickup
  --   float*  -- the power-up name rising `floatRise` px over the ship for
  --              `floatTime` s after picking it up
  pickup = {
    sheenEvery = 2.0, sheenTime = 0.35, sheenWidth = 0.22, sheenAlpha = 0.75,
    popTime = 0.25, popPeak = 1.25,
    dropRing = 18, collectRing = 26,
    floatTime = 0.8, floatRise = 14,
    -- Halo radius (x the pickup size) and how much a blink boosts it; the
    -- blink itself is a white ring around the badge (radius x size, px
    -- width), never over it, so the letter stays readable.
    glowSize = 0.65, blinkGlow = 1.3,
    blinkRing = 0.62, blinkWidth = 1.5, blinkAlpha = 0.9,
  },
  -- HUD and banner juice (src/hud.lua, Game:draw):
  --   scoreCatchUp -- s for the shown score to reach the real one
  --   *Kick        -- s of the punch on a score gain / combo step; *Scale =
  --                   its peak size (big = gains >= bigGain or a multiplier up)
  --   banner*      -- WAVE banners pop from bannerPopScale over bannerPop s; a
  --                   light band sweeps them from sweepStart for sweepTime s
  --   bonusCount   -- s for the wave bonus to count up from 0
  --   lost*        -- COMBO PERDIDO: px of shake and of the fall
  hud = {
    scoreCatchUp = 0.4, scoreKick = 0.14, bigGain = 1000,
    kickScale = 1.06, bigKickScale = 1.12, comboKick = 0.12,
    bannerTint = { 0.78, 0.84, 0.96 },   -- WAVE N: off-white, so the light band reads
    bannerPop = 0.22, bannerPopScale = 1.6, sweepStart = 0.12, sweepTime = 0.45, sweepWidth = 26,
    bonusCount = 0.6, lostShake = 3, lostDrop = 5,
  },
  -- Screen transitions (src/transition.lua): a diagonal wipe over `time` s
  -- with a band of `edge` color `edgeWidth` wide at the front and a `glow`
  -- wide fade of it behind (fractions of the screen diagonal).
  transition = { time = 0.35, edge = { 0.75, 0.85, 1.0 }, edgeWidth = 0.025, glow = 0.06 },
  -- Respawn beam: a column of light over the ship while it materializes
  -- (PLAYER.spawnFxTime), `height` px tall.
  beam = { height = 70, width = 10, alpha = 0.7 },
  -- Black veil over the sky during a match (lobby and game over keep it
  -- vivid), so the gameplay stands out.
  veil = 0.25,
  -- Scorch marks on the arena floor under big blasts: fixed slots, each
  -- lives `life` s and fades out over its last `fade` s. Drawn in the
  -- shadow layer (soft, at most as dark as a shadow): `alpha` is their
  -- share of the shadow darkness. Sizes in px.
  scorch = {
    slots = 16, life = 4.0, fade = 1.5, alpha = 0.7,
    tank = 34, player = 40, boss = 110, bossPop = 36,
  },
  -- Alpha of each emitter in the glow layer (0 = does not glow).
  emit = {
    shot = 0.9,          -- player shots (owner color)
    drone = 0.8,
    enemyShot = 0.55,    -- pink stars: a danger halo
    bossMissile = 0.8,
    spark = 0.9,         -- explosion sparks (smoke never glows)
    fire = 0.45,         -- explosion fire puffs
    flash = 0.5,         -- explosion core flash
    ring = 0.8,
    telegraph = 0.7,     -- kamikaze / sniper aim lines
    sniperShot = 0.9,    -- the sniper streak's red halo
    engine = 0.55,       -- player and boss engine flames (outer, colored)
    engineCore = 0.15,   -- their white core (blows out to a blob if strong)
    ship = 0.12,         -- faint aura in the player's color
    shield = 0.6,        -- invulnerability shield, bubble, respawn rings
    pickup = 0.28,       -- halo under the badge (kept low: the letter must read)
    door = 0.5,          -- blinking door lamp
    hitFlash = 0.35,     -- enemy/boss white hit flash
    rage = 0.6,          -- boss rage red pulse
    bossShield = 0.35,   -- boss entry shield (rim, hex and hit ripples)
    muzzle = 0.8,        -- muzzle flashes (player and boss)
    shotTrail = 0.6,     -- smear behind player shots
    ribbon = 0.5,        -- players' engine ribbon
  },
  -- Shockwaves: a ring that grows to `radius` px over `life` s and bends the
  -- picture behind it by up to `strength` px (fading as it grows); `width`
  -- is the ring's half-width. Callers may pass a gameplay radius instead
  -- (NOVA, bubble, salvo use theirs). At most 4 at once.
  shock = {
    tank   = { radius = 70,  strength = 4,  width = 12, life = 0.35 },
    salvo  = { radius = 40,  strength = 3,  width = 10, life = 0.30 },
    bubble = { radius = 50,  strength = 3,  width = 10, life = 0.35 },
    nova   = { radius = 130, strength = 6,  width = 16, life = 0.45 },
    player = { radius = 110, strength = 7,  width = 16, life = 0.50 },
    boss   = { radius = 300, strength = 10, width = 28, life = 0.90 },
    shield = { radius = 140, strength = 7,  width = 18, life = 0.50 },   -- boss shield pops
    debug  = { radius = 160, strength = 8,  width = 20, life = 0.60 },
  },
  -- Chromatic aberration pulses: RGB split in px at the arena's side edges
  -- (zero at the center), decaying `decay` px per second. Capped at `max`.
  aberration = { player = 3, boss = 3.5, debug = 3, max = 4, decay = 5 },
  -- Vignette: darkens the arena edges by `strength`, from `inner` to `outer`
  -- (1 = the arena's half width/height, so the corners are ~1.41). A player
  -- death tints it `hurtColor` at `hurt` opacity, fading `hurtDecay`/s.
  vignette = {
    strength = 0.35, inner = 0.75, outer = 1.45,
    hurtColor = { 0.85, 0.05, 0.08 }, hurt = 0.35, hurtDecay = 1.2,
  },
}

return Config
