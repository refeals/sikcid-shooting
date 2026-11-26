-- English: the default language and the reference for the others (a key
-- missing in es.lua or pt.lua shows this text). Keys and rules in
-- src/i18n.lua; the smoke test checks the three files have the same keys.
--
-- All caps, like the fonts' look (the power-up descriptions are the one
-- lowercase list). Mind the widths: tabs, option rows and the upgrade cards
-- are fixed-size, so a longer line may not fit (check with --shots).
return {
  decimal = ".",   -- in I18n.num ("2.5")

  -- Shared
  back_button = "BACK",
  hold_select_quit = "HOLD SELECT TO QUIT THE GAME",
  start_back_returns = "START OR BACK RETURNS",
  ready = "READY",
  disconnected = "DISCONNECTED",
  player_n = "PLAYER %d",
  tap_screen = "TAP THE SCREEN",
  best_solo = "BEST SOLO",
  best_duo = "BEST IN A DUO",
  duo_total = "DUO TOTAL",
  upgrades_title = "UPGRADES",
  act_move = "MOVE",
  act_aim = "AIM",
  wave = "WAVE ",   -- before a number (banners, HUD)

  -- Main menu
  menu_subtitle = "CO-OP ARENA SHOOTER FOR 1-2 PLAYERS",
  menu_play = "PLAY",
  menu_howto = "HOW TO PLAY",
  menu_records = "RECORDS",
  menu_options = "OPTIONS",
  menu_credits = "CREDITS",
  menu_quit = "QUIT",
  menu_hint_touch = "TAP AN OPTION",
  menu_hint = "D-PAD OR ARROWS SELECT   -   START, A OR ENTER CONFIRMS",

  -- OPTIONS
  opt_lang = "LANGUAGE",
  opt_fx = "VISUAL EFFECTS",
  opt_fx_levels = { "OFF", "LOW", "HIGH" },
  opt_music = "MUSIC",
  opt_sfx = "SOUND EFFECTS",
  opt_shake = "SCREEN SHAKE",
  opt_off = "OFF",
  opt_distortion = "DISTORTION",
  opt_distortion_values = { "OFF", "ON" },
  opt_fullscreen = "FULLSCREEN",
  opt_no_yes = { "NO", "YES" },
  opt_test = "TEST CONTROLS",
  opt_restore = "RESTORE DEFAULTS",
  opt_restore_asks = { "RESTORE? PRESS AGAIN" },
  opt_wipe = "ERASE RECORDS",
  opt_wipe_asks = { "ERASE THE RECORDS?", "SURE? THERE IS NO UNDO" },
  opt_restored = "DEFAULTS RESTORED",
  opt_wiped = "RECORDS ERASED",
  opt_hint_touch = "TAP THE ARROWS TO CHANGE",
  opt_hint = "D-PAD OR ARROWS: SELECT AND CHANGE   -   BACK OR B: RETURN",

  -- HOW TO PLAY: controls page (action names, then each device's bindings)
  howto_pad = "GAMEPAD",
  howto_keyboard = "KEYBOARD",
  howto_touch = "TOUCH SCREEN",
  howto_rules = "RULES",
  act_fire = "SHOOT",
  act_dash = "DASH",
  act_pause = "PAUSE",
  act_color = "SHIP COLOR (LOBBY)",
  act_quit = "QUIT THE GAME",
  bind_auto = "AUTOMATIC",
  pad_move = "LEFT STICK",
  pad_aim = "RIGHT STICK",
  pad_dash = "RB, LB OR B",
  pad_pause = "START OR BACK",
  pad_color = "D-PAD, Y: RANDOM",
  pad_quit = "HOLD SELECT",
  pad_note = "AIMING IS OPTIONAL: WITHOUT IT, THE SHIP SHOOTS THE NEAREST ENEMY BY ITSELF. THE D-PAD AIMS TOO.",
  kb_move = "WASD",
  kb_aim = "ARROWS",
  kb_dash = "SHIFT",
  kb_pause = "ENTER OR ESC",
  kb_color = "A/D, R: RANDOM",
  kb_quit = "HOLD ESC",
  kb_note = "AIMING IS OPTIONAL: WITHOUT IT, THE SHIP SHOOTS THE NEAREST ENEMY BY ITSELF.",
  touch_move = "LEFT HALF",
  touch_aim = "RIGHT HALF",
  touch_dash = "DASH BUTTON",
  touch_pause = "PAUSE BUTTON",
  touch_color = "SLOT ARROWS",
  touch_note = "WHERE YOUR FINGER LANDS BECOMES THE STICK'S CENTER. NO FINGER ON THE RIGHT: THE SHIP AIMS BY ITSELF.",
  -- HOW TO PLAY: rules page. Headings in Rocket Square ("0" is a box
  -- there): no digits in them.
  rule_waves_h = "WAVES",
  rule_waves = "ENEMIES COME IN THROUGH THE FOUR DOORS, IN BATCHES (THE DOOR BLINKS FIRST). "
    .. "THE WAVE ENDS WHEN NO ONE IS LEFT.",
  rule_combo_h = "COMBO",
  rule_combo = "EVERY KILL RESETS A %s S WINDOW. EVERY %d KILLS IN A ROW, "
    .. "THE SCORE MULTIPLIER GOES UP ONE STEP, UP TO X%d.",
  rule_rest_h = "BREATHER",
  rule_rest = "BETWEEN WAVES: A BONUS, A GUARANTEED POWER-UP AND %s S TO BREATHE, "
    .. "WITH THE COMBO AND POWER-UP TIMERS PAUSED.",
  rule_upgrades_h = "UPGRADES",
  rule_upgrades = "EVERY %d WAVES, EACH PLAYER PICKS A PERMANENT UPGRADE "
    .. "THAT LASTS UNTIL THE END OF THE MATCH.",
  rule_subboss_h = "SUB-BOSS",
  rule_subboss = "IN WAVES %d, %d, %d... A SUB-BOSS ENTERS MID-WAVE "
    .. "AND DROPS POWER-UPS WHEN IT FALLS.",
  rule_boss_h = "BOSS",
  rule_boss = "EVERY %d WAVES, A BOSS WAVE. EACH BOSS IS STRONGER THAN THE LAST.",
  howto_hint_touch = "TAP THE ARROWS TO TURN THE PAGE",
  howto_hint = "D-PAD OR ARROWS: PAGE   -   START: NEXT   -   BACK OR B: RETURN",

  -- RECORDS
  rec_scores = "SCORES",
  rec_best_match = "BEST MATCH",
  rec_machine = "THIS MACHINE",
  rec_wave_solo = "BEST WAVE SOLO",
  rec_wave_duo = "BEST WAVE IN A DUO",
  rec_combo = "LONGEST COMBO",
  rec_matches = "MATCHES",
  rec_kills = "ENEMIES DOWNED",
  rec_time = "TIME PLAYED",
  rec_time_fmt = "%dH %02dM",
  rec_bosses = "BOSSES",
  rec_subbosses = "SUB-BOSSES",

  -- CREDITS: { heading, line, line... } per section
  credits = {
    { "MUSIC",
      "MUSIC LOOP BUNDLE, BY ABSTRACTION (TALLBEARD STUDIOS) - CC0",
      "SUNBURN, CLOAK OF DARKNESS, NEVER MISS AND CRUSHING IT" },
    { "ART, FONTS AND COMBAT SOUNDS",
      "KENNEY (KENNEY.NL) - CC0",
      "SPACE SHOOTER EXTENSION, SIMPLE SPACE, PLANETS, UI PACK (SCI-FI),",
      "KENNEY FONTS AND SCI-FI SOUNDS" },
    { "OTHER SOUND EFFECTS",
      "MADE WITH SFXR (SFXR.ME)" },
    { "MADE WITH",
      "LÖVE (LOVE2D.ORG) - WEB VERSION WITH LOVE.JS (MIT)" },
  },

  -- Lobby
  lobby_title = "PLAYERS",
  lobby_press_start = "PRESS START",
  lobby_press_any = "PRESS ANY BUTTON",
  lobby_hint_touch_bound = "TAP TO START   -   THE ARROWS CHANGE THE COLOR",
  lobby_hint_touch = "TAP TO JOIN",
  lobby_hint_bound = "START TO BEGIN   -   BACK TO LEAVE THE SLOT",
  lobby_hint = "START TO JOIN   -   BACK RETURNS TO THE MENU",
  lobby_color_hint = "D-PAD CHANGES THE COLOR   -   Y PICKS ONE AT RANDOM",
  -- Lobby colors, by Config.PLAYER_PALETTE index
  color_name = { "BLUE", "GREEN", "CYAN", "LIME", "WHITE", "ORANGE", "LILAC", "GOLD" },

  -- Device names (lobby slot, input test)
  dev_keyboard = "KEYBOARD",
  dev_touch = "TOUCH",
  dev_pad = "GAMEPAD",
  dev_pad_unknown = "GAMEPAD ?",

  -- Briefing
  brief_title = "POWER-UPS",
  brief_pickup = "FLY OVER THEM TO PICK THEM UP",
  brief_stack = "%s ARE WEAPONS: PICKING ONE REPLACES THE OTHER.   %s STACK.",
  brief_dash = "DASH: %s  -  GOES THROUGH ENEMIES AND SHOTS",
  brief_or = " OR ",
  brief_dash_touch = "BUTTON ABOVE AIM",
  brief_upgrade = "EVERY %d WAVES: A PERMANENT UPGRADE",
  brief_start_touch = "TAP TO START",
  brief_start = "START BEGINS THE MATCH",
  brief_back = "BACK RETURNS TO PLAYER SELECT",

  -- Power-ups, by id (src/systems/powerups.lua). The icon letter is the
  -- same in every language.
  powerup_name = {
    spread = "SPREAD", rapid = "RAPID FIRE", missiles = "MISSILES", boots = "SPEED BOOTS",
    bubble = "BUBBLE", drone = "DRONE", damage = "DAMAGE X2", laser = "LASER",
    orbital = "ORBITAL SHIELD", slowmo = "SLOW TIME", nova = "NOVA", life = "EXTRA LIFE",
  },
  powerup_desc = {
    spread = "3 shots in a fan",
    rapid = "double fire rate",
    missiles = "homing missiles, 3 damage",
    boots = "40% more speed",
    bubble = "blocks 1 hit and pushes back",
    drone = "a drone that shoots by itself",
    damage = "doubles any weapon's damage",
    laser = "a beam that goes through everything",
    orbital = "orbs that destroy shots",
    slowmo = "enemies in slow motion",
    nova = "shockwave around you (instant)",
    life = "+1 life now (up to the max)",
  },

  -- Permanent upgrades, by id (src/systems/upgrades.lua). `desc`: one line
  -- per level (stats have one). Cards are narrow: keep lines short.
  upgrade_name = {
    cadence = "FIRE RATE", motor = "MOTOR", thruster = "THRUSTER", duration = "DURATION",
    hull = "ARMOR", magnet = "MAGNET", pierce = "PIERCING", rear = "REAR GUN",
    loyal = "WINGMAN", blade = "BLADE", recharge = "RECHARGE", ricochet = "RICOCHET",
    shock = "SHOCK", life = "+1 LIFE",
  },
  upgrade_desc = {
    cadence = { "+20% FIRE RATE" },
    motor = { "+12% SPEED" },
    thruster = { "THE DASH RECHARGES 20% FASTER" },
    duration = { "POWER-UPS LAST 35% LONGER" },
    hull = { "+1 LIFE NOW AND +1 MAX LIFE" },
    magnet = { "PULLS POWER-UPS TOWARD YOU" },
    pierce = { "SHOTS PIERCE 1 ENEMY", "SHOTS PIERCE 2 ENEMIES",
               "SHOTS PIERCE EVERY ENEMY" },
    rear = { "SHOOTS BACKWARD (HALF FIRE RATE)", "SHOOTS BACKWARD AT FULL RATE",
             "3 BACKWARD SHOTS IN A FAN" },
    loyal = { "PERMANENT DRONE (HALF FIRE RATE)", "THE DRONE FIRES AT FULL RATE",
              "A SECOND DRONE" },
    blade = { "DASH DEALS 3 DAMAGE TO WHAT IT CROSSES", "DASH DEALS 6 DAMAGE",
              "BLADE KILLS RECHARGE THE DASH" },
    recharge = { "GAIN A BUBBLE EVERY 30 S", "GAIN A BUBBLE EVERY 20 S",
                 "THE BUBBLE POPS WITH A NOVA" },
    ricochet = { "SHOTS BOUNCE OFF WALLS ONCE", "SHOTS BOUNCE TWICE",
                 "BOUNCED SHOTS HUNT ENEMIES" },
    shock = { "DASH ENDS WITH A MINI-NOVA", "BIGGER, STRONGER MINI-NOVA",
              "MINI-NOVA AT THE DASH START TOO" },
    life = { "+1 LIFE NOW (UP TO THE MAX)" },
  },

  -- Upgrade screen. Tab titles stay unaccented (see Config.ART.ui.tabH).
  up_title = "UPGRADE",
  up_title_boss = "BOSS REWARD",
  up_title_p = "P%d - UPGRADE",
  up_title_p_boss = "P%d - REWARD",
  up_pick = "PICK A PERMANENT UPGRADE",
  up_pick_boss = "PICK A PERMANENT REWARD",
  up_hint_touch = "TAP A CARD TO PICK IT",
  up_hint = "LEFT / RIGHT CHOOSES   -   START CONFIRMS",

  -- Enemies with a name on screen (debut banner, sub-boss alert and HP bar),
  -- by Config.ENEMIES key; bosses by Config.BOSS.variants id.
  enemy_name = {
    kamikaze = "KAMIKAZE", divisor = "SPLITTER", sniper = "SNIPER", carrier = "CARRIER",
    torre = "TOWER", ariete = "RAM", hidra = "HYDRA", colmeia = "HIVE",
  },
  boss_name = {
    destroyer = "DESTROYER", reaper = "REAPER", devourer = "DEVOURER",
    colossus = "COLOSSUS", sentinel = "SENTINEL",
  },

  -- In the arena
  game_over = "GAME OVER",
  press_start = "PRESS START",
  wave_cleared = " CLEARED",   -- after "WAVE N"
  bonus = "BONUS ",
  next_in = "NEXT IN ",
  enemies_left = "ENEMIES ",
  respawn = "P%d BACK IN %.1f",
  alert = "WARNING",
  new_enemy = "NEW: %s",
  hud_out = "OUT",
  hud_combo = "COMBO %d  x%d",
  hud_combo_lost = "COMBO LOST",
  hud_arena = "ARENA",

  -- Pause
  pause_title = "PAUSED",   -- big font: Rocket Square is wide, keep it short
  pause_hint = "START RESUMES   -   BACK QUITS THE MATCH",
  pause_tap = "TAP TO RESUME",
  pause_quit_button = "QUIT MATCH",
  pause_disconnected = "GAMEPAD DISCONNECTED",
  pause_waiting = "WAITING FOR PLAYER %d",
  pause_reconnect = "RECONNECT THE GAMEPAD TO CONTINUE",
  pause_back_quits = "BACK QUITS THE MATCH",
  pause_confirm = "CONFIRM",   -- tab title: no accents
  pause_quit_ask = "QUIT THE MATCH?",
  pause_confirm_hint = "BACK CONFIRMS   -   START KEEPS PLAYING",
  pause_confirm_tap = "TAP OUTSIDE TO KEEP PLAYING",
  pause_lost = "THIS MATCH'S PROGRESS WILL BE LOST",
  pause_none = "NONE YET",

  -- Results screen
  go_title = "GAME OVER",
  go_reached = "WAVE REACHED: ",
  go_cleared = "WAVES CLEARED: ",
  go_combo = "MAX COMBO  %d",
  go_duo_total = "DUO TOTAL  ",
  go_new_record = "NEW RECORD!",
  go_back_touch = "TAP TO RETURN TO THE LOBBY",
  go_back = "START RETURNS TO THE LOBBY",

  -- Input test
  it_title = "INPUT TEST",
  it_header = "%d device(s)  -  %d joystick(s) in SDL  -  deadzone %.2f radial",
  it_left = "LEFT",
  it_right = "RIGHT",
  it_quit = "QUIT",
  it_none = "no devices",
  it_unmapped = "NO GAMEPAD MAPPING (SDL)",
  it_unmapped_row = "%s  -  %d axes, %d buttons  -  guid %s",
  it_no_sdl = "no joystick visible to SDL",
  it_hint_standalone = "BACK OR F5 GOES TO THE MENU",
  it_hint = "BACK OR F5 CLOSES",
  it_hint_quit = "   -   HOLD ESC/SELECT TO QUIT",
  it_hint_scroll = "DOWN SCROLLS THE LIST   -   ",
}
