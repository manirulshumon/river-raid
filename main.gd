extends Node2D
## Riverwing prototype v0.6 - sound, tablets/TV, on-screen weapon choice
## (v0.6: music + sound effects; wider screens show more riverbank; TV remote and
##  gamepad controls; SUPPLY READY button lets you choose the weapon; pause menu
##  with sound settings and test tools; enemy bullets fly straight so you can dodge)
## (v0.5.1: weapon crates are earned: kill points fill the SUPPLY bar and a crate
##  is air-dropped when it is full; new weapon types unlock at score milestones)
## (v0.5: no permanent upgrades. Special weapons are crates on the river: fly over
##  one to take it. Each has its own 100% energy that runs down as you use it.
##  You carry two and switch between them. The battlefield adds a shield and the
##  Thunder Railgun automatically.)
## (v0.4.2: you can fly over the riverbanks in an emergency, but after a couple
##  of seconds over land a ground missile locks on and kills the jet in one hit)
## (v0.4.1: faster drawing for phones and the web: terrain is cached in chunks,
##  sprites and pixel text are baked into textures once and reused)
##
## Loop: fly up the river in a small stealth jet with a basic cannon; special
## weapons are rare crates you fly over (no menus). Every 5 minutes the river turns into a
## battlefield you must survive for 45 seconds; then the scenery changes
## (valley, snow, desert, jungle, city, volcanic, then round again, harder).
## Fortified zones: only the green corridor is safe; the red water outside it is
## covered by laser grids and flak batteries.
##
## Controls
##   Phone: drag to fly anywhere on screen. While your finger is down you fire.
##          Lift it to glide (fly over a FUEL tank without shooting it).
##   PC:    hold the mouse button and drag, or arrows / WASD to fly, hold Space to fire.
##          P or Esc = pause.
##   Editor-only test keys: B = next bridge, F = fortified zone now,
##          N = battlefield now, M = finish the battlefield (next scenery),
##          K = switch scenery now, G = god mode (no damage, no crashes),
##          J = get a random special weapon. Q or 1-3 = switch special weapon.

enum State { TITLE, PLAY, DEAD, PAUSED }
enum Mode { CRUISE, FORT, BATTLE }

const VW := 720.0            # design width; height expands to fit the phone
const ROW := 40.0            # one terrain row, in pixels
const COLW := 40.0           # one terrain column, in pixels
const COLS := 18
const LV := 16.0             # height of one voxel level (front face)
const STEER_SENS := 1.2
const CHUNK_ROWS := 8         # terrain rows cached per chunk

# pacing
const STAGE_TIME := 300.0    # seconds of normal flying before each battlefield (5 minutes)
const BATTLE_TIME := 45.0    # seconds you must survive on the battlefield
const FORT_ROWS := 60        # length of a fortified zone, in rows
const CORR_HW := 72.0        # half-width of the safe corridor in a fortified zone

# tuning: fuel, damage (in % of life) and defenses
const FUEL_DRAIN := 1.4      # % of the tank per second
const DEPOT_REFILL := 40.0
const BULLET_DMG := 1.0      # helicopter and soldier bullets
const FLAK_DMG := 2.0        # anti-aircraft guns
const BATTERY_DMG := 3.0     # fortified-zone flak batteries
const SHELL_DMG := 5.0       # tanks and warships
const SAM_DMG := 18.0        # guided missile from a SAM launcher
const LASER_DMG := 25.0      # laser grid
const STRIKE_DMG := 12.0     # artillery strike
const COVER_DMG := 20.0      # flying into a rock spire
const CRASH_DMG := 30.0      # ramming an enemy
const LOCK_TIME := 1.6       # seconds a SAM needs to lock on
const LAND_TIME := 2.5       # seconds over land before ground missiles launch
const FLARE_RECHARGE := 7.0  # seconds per flare

const LAND_KINDS := ["tank", "aa", "sam", "soldiers", "truck"]

# special weapons: picked up from crates, each with its own energy (100%)
# drain = % used per shot / per blast, or per second for beams and escorts
const SPECIALS := {
	"spread": {"name": "SPREAD GUN", "icon": "S", "col": Color("#ffb347"), "drain": 0.9},
	"laser": {"name": "LASER BEAM", "icon": "L", "col": Color("#ff4dd2"), "drain": 9.0},
	"homing": {"name": "HOMING MISSILES", "icon": "H", "col": Color("#ff6b6b"), "drain": 5.0},
	"rockets": {"name": "CLUSTER ROCKETS", "icon": "R", "col": Color("#f97316"), "drain": 8.0},
	"wingmen": {"name": "SUPPORT JETS", "icon": "W", "col": Color("#9be7ff"), "drain": 3.5},
	"drones": {"name": "GUARD DRONES", "icon": "D", "col": Color("#a3e635"), "drain": 3.0},
	"emp": {"name": "EMP BLAST", "icon": "E", "col": Color("#60a5fa"), "drain": 34.0},
	"rail": {"name": "THUNDER RAILGUN", "icon": "T", "col": Color("#facc15"), "drain": 1.6},
}
const CRATE_POOL := ["spread", "laser", "homing", "rockets", "wingmen", "drones", "emp"]
# weapon types unlock at these total scores (supply crates only contain unlocked types)
const UNLOCKS := [["spread", 0], ["homing", 2000], ["wingmen", 5000], ["rockets", 9000],
	["laser", 14000], ["drones", 20000], ["emp", 27000]]
const SUPPLY_FIRST := 1200.0     # kill points for the first supply drop
const SUPPLY_STEP := 400.0       # each later drop needs this much more
const SUPPLY_MAX := 3000.0
const FLARES_MAX := 2

# scenery for each stage, in order (loops)
const BIOMES := [
	{"name": "GREEN VALLEY", "prop": "tree",
		"land": Color("#7ccf55"), "land2": Color("#6fc44a"), "bank": Color("#f2d98d"),
		"water": Color("#2a8fd8"), "water2": Color("#2f97e0"), "shade": Color("#1a6eb0"),
		"tree": Color("#3fae4f"), "tree_side": Color("#237a35"), "rock": Color("#a3aab3"),
		"camo": Color("#6b7a3a"), "camo2": Color("#8a9a4a")},
	{"name": "FROZEN NORTH", "prop": "pine",
		"land": Color("#e9f1f8"), "land2": Color("#dbe7f2"), "bank": Color("#c2d8ea"),
		"water": Color("#2c6fb0"), "water2": Color("#3279bb"), "shade": Color("#1d4f85"),
		"tree": Color("#2f6b45"), "tree_side": Color("#1d4a2f"), "rock": Color("#8ea2b8"),
		"camo": Color("#c9d3dc"), "camo2": Color("#eef3f7")},
	{"name": "DESERT STORM", "prop": "cactus",
		"land": Color("#e8c47c"), "land2": Color("#dfb86e"), "bank": Color("#f3dda6"),
		"water": Color("#2a95b5"), "water2": Color("#2f9fbf"), "shade": Color("#1b7090"),
		"tree": Color("#4f9a45"), "tree_side": Color("#2f6b2a"), "rock": Color("#c47a45"),
		"camo": Color("#b8955a"), "camo2": Color("#d6b57a")},
	{"name": "JUNGLE DELTA", "prop": "jungle",
		"land": Color("#3fa34a"), "land2": Color("#379342"), "bank": Color("#9a7a4a"),
		"water": Color("#2b8a8a"), "water2": Color("#2f9494"), "shade": Color("#1b6464"),
		"tree": Color("#2e7d32"), "tree_side": Color("#1b5e20"), "rock": Color("#6b6f5a"),
		"camo": Color("#4d5e2e"), "camo2": Color("#6b7a3a")},
	{"name": "CITY RIVER", "prop": "city",
		"land": Color("#9aa3b0"), "land2": Color("#8f98a6"), "bank": Color("#c3cad4"),
		"water": Color("#2a6fb8"), "water2": Color("#2f78c2"), "shade": Color("#1b4f8a"),
		"tree": Color("#4caf50"), "tree_side": Color("#2e7d32"), "rock": Color("#7b8492"),
		"camo": Color("#5b6470"), "camo2": Color("#7b8592")},
	{"name": "VOLCANIC FRONT", "prop": "lava",
		"land": Color("#4a3f45"), "land2": Color("#40363b"), "bank": Color("#6e5c52"),
		"water": Color("#24508a"), "water2": Color("#285894"), "shade": Color("#163a66"),
		"tree": Color("#3a3034"), "tree_side": Color("#241d20"), "rock": Color("#2d2529"),
		"camo": Color("#3d3438"), "camo2": Color("#5a4c52")},
]

# pixel sprites
const F22 := [
	"......N......",
	".....NXN.....",
	".....XCX.....",
	"....XXCXX....",
	"....XXXXX....",
	"...LXXXXXL...",
	"..LLXXXXXLL..",
	".LLLXXXXXLLL.",
	"LLLLXXXXXLLLL",
	"....XXXXX....",
	"...TXX.XXT...",
	"..TTXX.XXTT..",
	"..TT.O.O.TT..",
]
const F22_COLS := {"N": Color("#4b5563"), "X": Color("#6b7686"), "L": Color("#8793a3"), "C": Color("#e0b23a"), "T": Color("#5b6573"), "O": Color("#ff9d2e")}
const HELI := [
	"..XXXX...",
	".XXCCXXXX",
	".XXXXXX.X",
	"..X..X...",
]
const BOAT := [
	"..XXXXXXX..",
	"XXGGXXXXXXX",
	"XXGGXXXXXXX",
	"..XXXXXXX..",
]
const SHIP := [
	"....XXXXXX....",
	"..XXXXXXXXXX..",
	"XXXXGGXXXTTXXX",
	"XXXXGGXXXTTXXX",
	"..XXXXXXXXXX..",
	"....XXXXXX....",
]
const TANK := [
	".TTTTT.",
	"TTTTTTT",
	"TTCCCTT",
	"TTCCCTT",
	"TTTTTTT",
	".TTBTT.",
	"...B...",
	"...B...",
]
const TRUCK := [
	".CCC.",
	"GGGGG",
	"GCCCG",
	"GCCCG",
	"GGGGG",
	"K...K",
]
const JET := [
	"...X......",
	"...XX.....",
	"XXXXXXXXX.",
	"XXXRRXXXXX",
	"XXXXXXXXX.",
	"...XX.....",
	"...X......",
]
const OTTER := [
	"..B.....B..",
	".BBB...BBB.",
	".BBBBBBBBB.",
	"BGGGBBBGGGB",
	"BGKGBBBGKGB",
	"BBBBLLLBBBB",
	"BBBLLNLLBBB",
	".BBLLLLLBB.",
	"..BBBBBBB..",
]
const OTTER_COLS := {"B": Color("#9a6334"), "L": Color("#f0d2ad"), "K": Color("#14181f"), "N": Color("#3b2412"), "G": Color("#22d3ee")}

# 5x7 pixel font
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
	"|": ["..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
}

const C_INK := Color("#0b2540")
const C_OUTLINE := Color("#1b2430")
const C_GOLD := Color("#ffd23f")
const C_CYAN := Color("#7ff3ff")
const C_RED := Color("#ff5a5f")
const C_SAFE := Color("#4ade80")
const C_DRONE := Color("#9be7ff")
const C_PANEL := Color(0.03, 0.094, 0.157, 0.84)

var state: int = State.TITLE
var ui_font: Font
var vh := 1280.0
var anchor_y := 950.0        # screen y where `dist` sits (the camera anchor)
var plane_y := 950.0         # the jet's screen y (it can fly up and down)
var t := 0.0
var shake_off := Vector2.ZERO
var shake_vec := Vector2.ZERO
var cv: CanvasItem = self      # canvas the shared draw helpers paint on
var chunks := {}               # chunk index -> Node2D holding cached terrain
var wrecks: Array = []         # burning wrecks to animate: [x, w_top, hash]
var spr_cache := {}
var txt_cache := {}
var sb_cache := {}

# run state
var px := 360.0
var pvel := Vector2.ZERO
var last_ppos := Vector2.ZERO
var dist := 0.0
var speed := 0.0
var fuel := 100.0
var max_fuel := 100.0
var score := 0.0
var best := 0
var coins := 0
var kills := 0
var bridges_down := 0
var invuln := 0.0
var health := 100.0
var hurt_t := 0.0
var firing := false
var fire_t := 0.0
var missile_t := 0.0
var flares := 2
var flare_rc := 0.0
var flare_cd := 0.0
var death_reason := ""
var dead_t := 0.0
var shake := 0.0

# stages and phases
var stage := 0
var mode: int = Mode.CRUISE
var stage_clock := 0.0
var battle_t := 0.0
var fort_clock := 0.0
var next_fort := 60.0
var strike_t := 3.0
var amb_t := 0.5
var banner := {}
var toasts: Array = []
var lock_level := 0.0
var masked := false
var out_corridor := false
var slots: Array = []           # carried special weapons: {"id", "energy", "war"}
var sel := 0                    # selected slot
var shield_hp := 0.0
var shield_fx := 0.0
var spec_t := 0.0
var laser_on := false
var laser_top := 0.0
var laser_tick := 0.0
var rail_fx := 0.0
var rail_x := 0.0
var emp_fx := 0.0
var emp_cd := 0.0
var weapons_got := 0
var supply := 0.0               # kill points collected toward the next supply drop
var supply_need := SUPPLY_FIRST
var unlocked := 1               # how many entries of UNLOCKS are available
var over_land := false
var land_t := 0.0
var land_fired := false

# input
var touching := false
var god := false
var fire_latch := false         # TV remote: OK toggles firing on/off
var enter_down := false
var enter_t := 0.0
var enter_long := false
var xoff := 0.0                 # extra width on each side of the 720 px core (tablets, TV)
var chunk_cols := -1
var tv_mode := false
var supply_ready := false
var picking := false
var pick_t := 0.0
var pick_focus := 0
var menu_focus := 0
var music_on := true
var sfx_on := true
var autotest := false
var at_t := 0.0
var at_step := 0
# audio
var snd := {}
var sfx_players: Array = []
var sfx_next := 0
var sfx_last := {}
var music_tracks := {}
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_cur := ""
var music_fade := 1.0
var laser_player: AudioStreamPlayer
var beep_t := 0.0

# terrain generator (one entry per row)
var rows_c := PackedFloat32Array()   # river centre
var rows_h := PackedFloat32Array()   # river half-width
var rows_cc := PackedFloat32Array()  # safe corridor centre (fortified rows), -1 elsewhere
var rows_b := PackedInt32Array()     # scenery (biome) index
var rows_m := PackedInt32Array()     # Mode the row was built for
var rows_wl := PackedInt32Array()    # first water column of the row
var rows_wr := PackedInt32Array()    # last water column of the row (wl > wr: no water)
var gen_c := 360.0
var gen_h := 230.0
var gen_tc := 360.0
var gen_th := 230.0
var gen_change := 12
var gen_mode: int = Mode.CRUISE
var gen_biome := 0
var fort_i := 0
var fort_phase := 0.0
var cover_gap := 4
var next_depot_row := 40
var next_bridge_row := 150
var last_bridge_row := -100

# entities (dictionaries; world space: x across, w = distance up the river)
var enemies: Array = []
var depots: Array = []
var kits: Array = []
var wcrates: Array = []
var rockets: Array = []
var bridges: Array = []
var covers: Array = []
var lasers: Array = []
var strikes: Array = []
var bullets: Array = []
var missiles: Array = []
var debris: Array = []
var smoke: Array = []
var flashes: Array = []
var coin_fx: Array = []
var popups: Array = []
# screen space
var eshots: Array = []
var emissiles: Array = []
var flare_fx: Array = []


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Rubik", "Segoe UI", "Roboto", "Arial"])
	sf.font_weight = 700
	ui_font = sf
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	randomize()
	get_tree().quit_on_go_back = false
	autotest = OS.get_cmdline_user_args().has("--autotest")
	_setup_orientation()
	_setup_audio()
	_load_best()
	_reset()
	state = State.TITLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == State.PLAY and not autotest:
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _setup_orientation() -> void:
	# phones stay portrait; tablets may rotate; TVs are landscape
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	if not DisplayServer.is_touchscreen_available():
		tv_mode = true
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		return
	var px_size := Vector2(DisplayServer.screen_get_size())
	var dpi := float(maxi(DisplayServer.screen_get_dpi(), 1))
	if px_size.length() / dpi >= 7.0:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)


func _pause() -> void:
	if state == State.PLAY:
		state = State.PAUSED
		touching = false
		enter_down = false
		menu_focus = 0
		_sfx("tap")


func _back() -> void:
	match state:
		State.PLAY:
			if picking:
				picking = false
			else:
				_pause()
		State.PAUSED:
			state = State.PLAY
		State.DEAD:
			state = State.TITLE
		State.TITLE:
			get_tree().quit()


func _reset() -> void:
	for a in [enemies, depots, kits, wcrates, rockets, bridges, covers, lasers, strikes, bullets, missiles,
			debris, smoke, flashes, coin_fx, popups, eshots, emissiles, flare_fx, toasts]:
		a.clear()
	banner = {}
	rows_c = PackedFloat32Array()
	rows_h = PackedFloat32Array()
	rows_cc = PackedFloat32Array()
	rows_b = PackedInt32Array()
	rows_m = PackedInt32Array()
	rows_wl = PackedInt32Array()
	rows_wr = PackedInt32Array()
	for k in chunks.keys():
		chunks[k].queue_free()
	chunks.clear()
	wrecks.clear()
	gen_c = 360.0
	gen_h = 230.0
	gen_tc = 360.0
	gen_th = 230.0
	gen_change = 12
	gen_mode = Mode.CRUISE
	gen_biome = 0
	fort_i = 0
	cover_gap = 4
	next_depot_row = 40
	next_bridge_row = 150
	last_bridge_row = -100
	px = 360.0
	plane_y = anchor_y
	pvel = Vector2.ZERO
	last_ppos = Vector2(px, plane_y)
	dist = 0.0
	speed = 0.0
	fuel = 100.0
	max_fuel = 100.0
	score = 0.0
	coins = 0
	kills = 0
	bridges_down = 0
	invuln = 0.0
	health = 100.0
	hurt_t = 0.0
	flares = 2
	flare_rc = 0.0
	flare_cd = 0.0
	stage = 0
	mode = Mode.CRUISE
	stage_clock = 0.0
	battle_t = 0.0
	fort_clock = 0.0
	next_fort = randf_range(50.0, 65.0)
	lock_level = 0.0
	masked = false
	out_corridor = false
	over_land = false
	land_t = 0.0
	land_fired = false
	slots = []
	sel = 0
	supply_ready = false
	picking = false
	fire_latch = false
	shield_hp = 0.0
	shield_fx = 0.0
	spec_t = 0.0
	laser_on = false
	rail_fx = 0.0
	emp_fx = 0.0
	emp_cd = 0.0
	weapons_got = 0
	supply = 0.0
	supply_need = SUPPLY_FIRST
	unlocked = 1
	_ensure_rows(int((vh + 400.0) / ROW))


# ---------------------------------------------------------------- terrain

func _ensure_rows(upto: int) -> void:
	while rows_c.size() <= upto:
		_gen_row(rows_c.size())


func _difficulty() -> float:
	return float(stage) + clampf(stage_clock / STAGE_TIME, 0.0, 1.0)


func _gen_row(r: int) -> void:
	var m: int = gen_mode
	var c := 360.0
	var h := 230.0
	var cc := -1.0
	if m == Mode.FORT:
		var i := fort_i
		fort_i += 1
		gen_c = move_toward(gen_c, 360.0, 18.0)
		gen_h = move_toward(gen_h, 290.0, 14.0)
		c = gen_c
		h = gen_h
		if i >= 6 and i < FORT_ROWS - 4:
			cc = 360.0 + 165.0 * sin(fort_phase)
			fort_phase += 0.075
			cc = clampf(cc, c - h + CORR_HW + 24.0, c + h - CORR_HW - 24.0)
		if fort_i >= FORT_ROWS:
			gen_mode = Mode.CRUISE
			gen_change = 0
	elif m == Mode.BATTLE:
		if gen_change <= 0:
			gen_th = randf_range(150.0, 180.0)
			gen_tc = 360.0 + randf_range(-25.0, 25.0)
			gen_change = randi_range(8, 16)
		gen_change -= 1
		gen_c = move_toward(gen_c, gen_tc, 10.0)
		gen_h = move_toward(gen_h, gen_th, 10.0)
		c = gen_c
		h = gen_h
	else:
		var diff := _difficulty()
		if gen_change <= 0:
			var hmin := maxf(105.0, 195.0 - diff * 16.0)
			var hmax := maxf(hmin + 20.0, 265.0 - diff * 12.0)
			gen_th = randf_range(hmin, hmax)
			gen_tc = randf_range(gen_th + 30.0, VW - gen_th - 30.0)
			gen_change = randi_range(8, 20)
		gen_change -= 1
		gen_c = move_toward(gen_c, gen_tc, 16.0)
		gen_h = move_toward(gen_h, gen_th, 9.0)
		c = gen_c
		h = gen_h
		var d: int = mini(next_bridge_row - r, r - last_bridge_row)
		if d < 10:
			var k := float(maxi(d, 0)) / 10.0
			c = lerpf(360.0, c, k)
			h = lerpf(150.0, h, k)
	if r < 12:
		h = maxf(h, 230.0)
	c = clampf(c, h + 20.0, VW - h - 20.0)
	rows_c.append(c)
	rows_h.append(h)
	rows_cc.append(cc)
	rows_b.append(gen_biome)
	rows_m.append(m)
	var wl := clampi(int(ceil((c - h - COLW * 0.5) / COLW)), 0, COLS)
	var wr := clampi(int(floor((c + h - COLW * 0.5) / COLW)), -1, COLS - 1)
	rows_wl.append(wl)
	rows_wr.append(wr)

	# no bridges inside fortified zones or battlefields
	if m != Mode.CRUISE and r >= next_bridge_row - 12:
		next_bridge_row = r + 40
	var span := _water_span(r)
	if m == Mode.CRUISE and r == next_bridge_row:
		_spawn_bridge(r)
		last_bridge_row = r
		next_bridge_row = r + randi_range(140, 170)
		return
	if r < 16:
		return
	if m == Mode.CRUISE and mini(next_bridge_row - r, r - last_bridge_row) < 6:
		return
	match m:
		Mode.FORT:
			_spawn_fort_row(r, span, cc)
		Mode.BATTLE:
			_spawn_battle_row(r, span)
		_:
			_spawn_cruise_row(r, span)


func _spawn_cruise_row(r: int, span: Vector2) -> void:
	if r >= next_depot_row:
		_spawn_depot(r, span, -1.0)
		return
	var diff := _difficulty()
	if randf() < 0.008:
		_spawn_kit(r, span, -1.0)
	elif randf() < 0.10 + 0.03 * diff:
		_spawn_enemy(r, span)
	elif randf() < 0.025 + 0.015 * diff:
		_spawn_ground(r, span, _pick_ground(false))


func _spawn_fort_row(r: int, span: Vector2, cc: float) -> void:
	if cc < 0.0:
		return
	var i := fort_i - 1
	var w := r * ROW + ROW * 0.5
	if i % 5 == 0 and i >= 9 and i < FORT_ROWS - 8:
		var segs: Array = []
		if cc - CORR_HW - span.x > 20.0:
			segs.append(Vector2(span.x, cc - CORR_HW))
		if span.y - (cc + CORR_HW) > 20.0:
			segs.append(Vector2(cc + CORR_HW, span.y))
		if not segs.is_empty():
			lasers.append({"w": w, "segs": segs})
		return
	if i % 6 == 3:
		var lz := Vector2(span.x + 40.0, cc - CORR_HW - 44.0)
		var rz := Vector2(cc + CORR_HW + 44.0, span.y - 40.0)
		var zone := lz if (lz.y - lz.x) > (rz.y - rz.x) else rz
		if zone.y - zone.x >= 0.0:
			var e := _mk_enemy("battery", randf_range(zone.x, zone.y), w, 0.0, 6, Vector2(60, 60), 200)
			e["fire_t"] = randf_range(0.1, 0.6)
			enemies.append(e)
		return
	if r >= next_depot_row and i > 10:
		_spawn_depot(r, span, cc)
	elif randf() < 0.02:
		_spawn_kit(r, span, cc)


func _spawn_battle_row(r: int, span: Vector2) -> void:
	if r >= next_depot_row:
		_spawn_depot(r, span, -1.0)
		return
	var w := r * ROW + ROW * 0.5
	cover_gap -= 1
	if cover_gap <= 0 and span.y - span.x > 200.0:
		cover_gap = randi_range(4, 7)
		var mid := (span.x + span.y) * 0.5
		var half := (span.y - span.x) * 0.5
		var side := -1.0 if randf() < 0.5 else 1.0
		var x := clampf(mid + side * randf_range(30.0, half - 60.0), span.x + 44.0, span.y - 44.0)
		covers.append({"x": x, "w": w, "size": Vector2(64, 56)})
		return
	var diff := _difficulty()
	if randf() < 0.26 + 0.05 * diff:
		_spawn_ground(r, span, _pick_ground(true))
	if randf() < 0.014:
		_spawn_kit(r, span, -1.0)
	elif randf() < 0.09 + 0.02 * diff:
		_spawn_enemy(r, span)


func _spawn_depot(r: int, span: Vector2, cx: float) -> void:
	var dx := cx
	if dx < 0.0:
		dx = (span.x + span.y) * 0.5
		if span.y - span.x > 100.0:
			dx = randf_range(span.x + 44.0, span.y - 44.0)
	depots.append({"x": dx, "w": r * ROW + ROW * 0.5, "hp": 3, "size": Vector2(80, 96), "dead": false, "flash": 0.0})
	next_depot_row = r + randi_range(100, 150)


func _spawn_kit(r: int, span: Vector2, cx: float) -> void:
	var roll := randf()
	var amt := 5
	if roll > 0.9:
		amt = 20
	elif roll > 0.6:
		amt = 10
	var x := cx
	if x < 0.0:
		x = (span.x + span.y) * 0.5
		if span.y - span.x > 90.0:
			x = randf_range(span.x + 36.0, span.y - 36.0)
	kits.append({"x": x, "w": r * ROW + ROW * 0.5, "amt": amt, "size": Vector2(56, 64), "dead": false})


func _add_supply(pts: float) -> void:
	if supply_ready:
		return
	supply += pts
	if supply >= supply_need:
		supply = supply_need
		supply_ready = true
		toasts.append({"text": "SUPPLY READY! TAP TO CHOOSE", "life": 2.4})
		_sfx("supply_ready")
		_buzz(60)


func _open_picker() -> void:
	if not supply_ready or picking:
		return
	picking = true
	pick_t = 6.0
	pick_focus = 0
	_sfx("tap")


func _pick_choose(i: int) -> void:
	if not picking:
		return
	i = clampi(i, 0, maxi(unlocked - 1, 0))
	picking = false
	supply_ready = false
	supply = 0.0
	supply_need = minf(supply_need + SUPPLY_STEP, SUPPLY_MAX)
	_supply_drop(String(UNLOCKS[i][0]))


func _supply_drop(choice := "") -> void:
	# a crate parachutes onto the river just above the top of the screen
	var w := dist + anchor_y + 160.0
	for b in bridges:
		if b["alive"] and absf(b["w"] - w) < 100.0:
			w = b["w"] + 140.0
	var r := _row_of(w)
	var span := _water_span(r)
	var x := (span.x + span.y) * 0.5
	if rows_m[r] == Mode.FORT and rows_cc[r] >= 0.0:
		x = rows_cc[r]
	elif span.y - span.x > 100.0:
		x = randf_range(span.x + 40.0, span.y - 40.0)
	var pool: Array = []
	for i in unlocked:
		pool.append(UNLOCKS[i][0])
	var id: String = pool[randi() % pool.size()] if choice == "" else choice
	wcrates.append({"x": x, "w": r * ROW + ROW * 0.5, "id": id, "size": Vector2(60, 64), "dead": false})
	toasts.append({"text": "SUPPLY DROP: " + String(SPECIALS[id]["name"]), "life": 2.4})
	_buzz(40)


func _check_unlocks() -> void:
	while unlocked < UNLOCKS.size() and score >= float(UNLOCKS[unlocked][1]):
		var nm: String = SPECIALS[UNLOCKS[unlocked][0]]["name"]
		unlocked += 1
		toasts.append({"text": "UNLOCKED: " + nm, "life": 2.6})
		_sfx("unlock")
		_buzz(60)


func _spawn_bridge(r: int) -> void:
	var hp := 12 + 4 * stage
	var w := r * ROW + ROW * 0.5
	bridges.append({"w": w, "hp": hp, "maxhp": hp, "alive": true, "hit": 0.0})
	var span := _water_span(r)
	var spots: Array = [clampf(span.x - 44.0, 34.0, VW - 34.0), clampf(span.y + 44.0, 34.0, VW - 34.0)]
	spots.shuffle()
	var n := 1 if stage == 0 else 2
	for i in n:
		enemies.append(_mk_enemy("tank", spots[i], w, 0.0, 4, Vector2(52, 56), 150))


func _mk_enemy(kind: String, x: float, w: float, vx: float, hp: int, size: Vector2, pts: int) -> Dictionary:
	return {
		"kind": kind, "x": x, "w": w, "vx": vx, "hp": hp, "maxhp": hp, "size": size, "pts": pts,
		"dead": false, "active": false, "flash": 0.0,
		"fire_t": randf_range(0.6, 1.6), "burst": 0, "burst_t": 0.0,
		"lock": 0.0, "cool": randf_range(0.8, 2.0), "masked": false,
	}


func _pick_ground(battle: bool) -> String:
	var roll := randf()
	if battle:
		if roll < 0.22:
			return "soldiers"
		elif roll < 0.34:
			return "truck"
		elif roll < 0.58:
			return "tank"
		elif roll < 0.80:
			return "aa"
		return "sam"
	if roll < 0.45:
		return "tank"
	elif roll < 0.75:
		return "aa"
	elif roll < 0.9:
		return "truck"
	return "sam" if stage >= 1 else "soldiers"


func _spawn_ground(r: int, span: Vector2, kind: String) -> void:
	var size := Vector2(52, 56)
	var hp := 4
	var pts := 150
	match kind:
		"aa":
			size = Vector2(48, 48)
			hp = 3
			pts = 140
		"sam":
			size = Vector2(52, 60)
			hp = 4
			pts = 250
		"soldiers":
			size = Vector2(64, 44)
			hp = 2
			pts = 100
		"truck":
			size = Vector2(40, 52)
			hp = 2
			pts = 80
	var need := size.x + 24.0
	var opts: Array = []
	var lmin := maxf(12.0 - xoff, span.x - 300.0)
	var rmax := minf(VW - 12.0 + xoff, span.y + 300.0)
	if span.x - lmin >= need:
		opts.append(Vector2(lmin + size.x * 0.5, span.x - 12.0 - size.x * 0.5))
	if rmax - span.y >= need:
		opts.append(Vector2(span.y + 12.0 + size.x * 0.5, rmax - size.x * 0.5))
	if opts.is_empty():
		return
	var o: Vector2 = opts[randi() % opts.size()]
	var x := randf_range(o.x, maxf(o.x, o.y))
	enemies.append(_mk_enemy(kind, x, r * ROW + ROW * 0.5, 0.0, hp, size, pts))


func _spawn_enemy(r: int, span: Vector2) -> void:
	var roll := randf()
	var kind := "boat"
	if stage >= 1 and roll < 0.15:
		kind = "jet"
	elif roll < 0.45:
		kind = "heli"
	elif roll < 0.72 and span.y - span.x > 150.0:
		kind = "ship"
	var size := Vector2(84, 34)
	var hp := 2
	var spd := randf_range(70.0, 120.0)
	var pts := 60
	if kind == "heli":
		size = Vector2(76, 40)
		hp = 1
		spd = randf_range(110.0, 170.0)
		pts = 90
	elif kind == "ship":
		size = Vector2(112, 48)
		hp = 5
		spd = randf_range(45.0, 75.0)
		pts = 150
	elif kind == "jet":
		size = Vector2(76, 50)
		hp = 1
		spd = randf_range(360.0, 440.0)
		pts = 120
	var dir := 1.0 if randf() < 0.5 else -1.0
	var x := (span.x + span.y) * 0.5
	if kind == "jet":
		x = -60.0 - xoff if dir > 0.0 else VW + 60.0 + xoff
	elif span.y - span.x > size.x + 8.0:
		x = randf_range(span.x + size.x * 0.5, span.y - size.x * 0.5)
	enemies.append(_mk_enemy(kind, x, r * ROW + ROW * 0.5, spd * dir, hp, size, pts))


func _row_of(w: float) -> int:
	var r := maxi(int(floor(w / ROW)), 0)
	_ensure_rows(r)
	return r


func _cell_is_water(r: int, col: int) -> bool:
	if col < 0 or col >= COLS:
		return false
	var rr := maxi(r, 0)
	_ensure_rows(rr)
	return col >= rows_wl[rr] and col <= rows_wr[rr]


func _is_water(x: float, w: float) -> bool:
	return _cell_is_water(_row_of(w), int(floor(x / COLW)))


func _water_span(r: int) -> Vector2:
	var rr := maxi(r, 0)
	_ensure_rows(rr)
	var first: int = rows_wl[rr]
	var last: int = rows_wr[rr]
	if first > last:
		return Vector2(300.0, 420.0)
	return Vector2(first * COLW, (last + 1) * COLW)


func _sy(w: float) -> float:
	return anchor_y - (w - dist)


func _wy(sy: float) -> float:
	return dist + (anchor_y - sy)


func _pw() -> float:
	return _wy(plane_y)


func _ymin() -> float:
	return 300.0


func _ymax() -> float:
	return vh - 324.0


func _hash(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663)) % 1000


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	t += dt
	var vsize := get_viewport_rect().size
	vh = vsize.y
	xoff = maxf((vsize.x - VW) * 0.5, 0.0)
	anchor_y = vh - 330.0
	if autotest:
		_autotest(dt)
	# TV remote: holding OK switches weapon (or opens the supply picker)
	if enter_down and not enter_long and t - enter_t > 0.45:
		enter_long = true
		if state == State.PLAY:
			if supply_ready:
				_open_picker()
			elif slots.size() > 1:
				_select_slot((sel + 1) % slots.size())
	if state == State.TITLE:
		plane_y = anchor_y
	plane_y = clampf(plane_y, _ymin(), _ymax())
	shake = move_toward(shake, 0.0, dt * 40.0)
	shake_vec = Vector2.ZERO
	if shake > 0.1 and state != State.PAUSED:
		shake_vec = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	var gdt := dt
	if picking and state == State.PLAY:
		gdt = dt * 0.3                 # slow motion while choosing a supply drop
		pick_t -= dt
		if pick_t <= 0.0:
			_pick_choose(randi() % maxi(unlocked, 1))
	match state:
		State.PLAY:
			_update_play(gdt)
		State.DEAD:
			dead_t += dt
	if state != State.PAUSED:
		_update_fx(gdt)
	_update_audio(dt)
	_update_chunks()
	queue_redraw()


func _update_play(dt: float) -> void:
	# flying: keyboard (the finger/mouse is handled in _input)
	var kb := Vector2.ZERO
	if not picking:
		kb = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down", 0.2)
		if Input.is_key_pressed(KEY_A):
			kb.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			kb.x += 1.0
		if Input.is_key_pressed(KEY_W):
			kb.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			kb.y += 1.0
		kb = kb.limit_length(1.0)
	px = clampf(px + kb.x * 560.0 * dt, 20.0 - xoff, VW - 20.0 + xoff)
	plane_y = clampf(plane_y + kb.y * 520.0 * dt, _ymin(), _ymax())
	var pp := Vector2(px, plane_y)
	pvel = pvel.lerp((pp - last_ppos) / dt, clampf(dt * 8.0, 0.0, 1.0))
	last_ppos = pp
	firing = touching or fire_latch or Input.is_key_pressed(KEY_SPACE) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5

	var base := minf(290.0 + float(stage) * 20.0 + 30.0 * clampf(stage_clock / STAGE_TIME, 0.0, 1.0), 470.0)
	speed = move_toward(speed, base, 600.0 * dt)
	dist += speed * dt
	score += speed * dt * 0.05
	_ensure_rows(int((dist + anchor_y + 200.0) / ROW) + 2)
	_update_phase(dt)
	_check_unlocks()

	# fuel and pickups
	var drain := FUEL_DRAIN
	fuel -= drain * dt
	hurt_t = maxf(hurt_t - dt, 0.0)
	var prect := _plane_rect()
	for d in depots:
		if not d["dead"] and prect.intersects(_ent_rect(d)):
			d["dead"] = true
			var got := minf(DEPOT_REFILL, max_fuel - fuel)
			fuel += got
			_popup("+" + str(int(round(got))) + " FUEL", d["x"], _sy(d["w"]) - 60.0, 4.0, C_CYAN)
			_sfx("fuel")
			_burst(d["x"], d["w"], [C_CYAN, Color.WHITE], 10, 0.6)
			_buzz(30)
	for c in wcrates:
		if not c["dead"] and prect.intersects(_ent_rect(c)):
			c["dead"] = true
			var cid: String = c["id"]
			_burst(c["x"], c["w"], [SPECIALS[cid]["col"], Color.WHITE], 14, 0.8)
			_pickup_weapon(cid)
	for k in kits:
		if not k["dead"] and prect.intersects(_ent_rect(k)):
			k["dead"] = true
			var amt: int = k["amt"]
			health = minf(100.0, health + float(amt))
			_popup("+" + str(amt) + "% LIFE", k["x"], _sy(k["w"]) - 60.0, 4.0, Color("#86efac"))
			_sfx("life")
			_burst(k["x"], k["w"], [C_SAFE, Color.WHITE], 12, 0.7)
			_buzz(30)
	fuel = minf(fuel, max_fuel)
	if fuel <= 0.0:
		fuel = 0.0
		_die("OUT OF FUEL")
		return

	# corridor check (fortified zones)
	var pw := _pw()
	var prow := _row_of(pw)
	out_corridor = false
	if rows_m[prow] == Mode.FORT and rows_cc[prow] >= 0.0:
		out_corridor = absf(px - rows_cc[prow]) > CORR_HW

	# over land: allowed for a moment, then ground missiles launch
	over_land = not _is_water(px, pw)
	if over_land:
		if land_t <= 0.0:
			_buzz(60)
		land_t += dt
		if land_t >= _land_limit() and not land_fired:
			land_fired = true
			_launch_land_missile()
	else:
		land_t = maxf(land_t - dt * 3.0, 0.0)
		land_fired = false

	_update_weapons(dt)
	_update_enemies(dt)
	_update_shots(dt)
	_update_rockets(dt)
	_update_eshots(dt)
	_update_emissiles(dt)
	_update_strikes(dt)
	_update_defense(dt)
	if state != State.PLAY:
		return

	# collisions with the jet
	invuln = maxf(invuln - dt, 0.0)
	var hit := _hitbox()
	if invuln <= 0.0:
		for e in enemies:
			if e["active"] and not e["dead"] and not LAND_KINDS.has(e["kind"]) and hit.intersects(_ent_rect(e)):
				_kill_enemy(e)
				_damage(CRASH_DMG)
				invuln = maxf(invuln, 1.0)
				break
	if invuln <= 0.0 and state == State.PLAY:
		for c in covers:
			if hit.intersects(_ent_rect(c)):
				_damage(COVER_DMG)
				invuln = 1.0
				_popup("ROCK!", px, plane_y - 80.0, 3.5, C_RED)
				break
	if invuln <= 0.0 and state == State.PLAY:
		for L in lasers:
			var sy := _sy(L["w"])
			if absf(sy - plane_y) > 40.0:
				continue
			for s in L["segs"]:
				var seg: Vector2 = s
				if hit.intersects(Rect2(seg.x, sy - 5.0, seg.y - seg.x, 10.0)):
					_damage(LASER_DMG)
					invuln = 0.9
					_flash(px, pw, 50.0)
					_popup("LASER!", px, plane_y - 80.0, 4.0, C_RED)
					_sfx("zap")
					break
			if invuln > 0.0:
				break
	if state == State.PLAY:
		for b in bridges:
			if b["alive"] and absf(pw - b["w"]) < 28.0:
				if shield_hp > 0.0:
					_destroy_bridge(b)
					shield_hp = 0.0
					invuln = 1.0
					_popup("SHIELD SAVED YOU!", px, plane_y - 100.0, 4.0, C_CYAN)
					break
				_die("YOU HIT THE BRIDGE")
				return

	var low := dist - (vh - anchor_y) - 300.0
	enemies = enemies.filter(func(e): return not e["dead"] and e["w"] > low)
	depots = depots.filter(func(e): return not e["dead"] and e["w"] > low)
	kits = kits.filter(func(e): return not e["dead"] and e["w"] > low)
	wcrates = wcrates.filter(func(e): return not e["dead"] and e["w"] > low)
	covers = covers.filter(func(e): return e["w"] > low)
	lasers = lasers.filter(func(e): return e["w"] > low)
	bridges = bridges.filter(func(e): return e["w"] > low)


func _update_phase(dt: float) -> void:
	stage_clock += dt
	if mode == Mode.CRUISE:
		fort_clock += dt
		if gen_mode == Mode.CRUISE and fort_clock >= next_fort and stage_clock < STAGE_TIME - 30.0:
			_start_fort()
		if stage_clock >= STAGE_TIME and gen_mode == Mode.CRUISE:
			_start_battle()
	elif mode == Mode.BATTLE:
		battle_t -= dt
		strike_t -= dt
		if strike_t <= 0.0:
			strike_t = maxf(randf_range(1.4, 2.2) - 0.1 * float(stage), 0.8)
			var tw := _pw() + speed * 1.2 + randf_range(-60.0, 220.0)
			var tx := clampf(px + randf_range(-140.0, 140.0), 40.0, VW - 40.0)
			strikes.append({"x": tx, "w": tw, "t": 1.2, "max": 1.2})
		amb_t -= dt
		if amb_t <= 0.0:
			amb_t = randf_range(0.25, 0.6)
			var aw := dist + randf_range(-200.0, anchor_y)
			var span := _water_span(_row_of(aw))
			var ax := randf_range(10.0, maxf(span.x - 10.0, 12.0)) if randf() < 0.5 else randf_range(minf(span.y + 10.0, VW - 12.0), VW - 10.0)
			_flash(ax, aw, randf_range(30.0, 60.0))
			_burst(ax, aw, [Color("#6b6b6b"), Color("#ffb347"), Color("#3a3a3a")], 5, 0.5)
		if battle_t <= 0.0:
			_end_battle()


func _start_fort() -> void:
	gen_mode = Mode.FORT
	fort_i = 0
	fort_phase = 0.0 if randf() < 0.5 else PI
	fort_clock = 0.0
	next_fort = randf_range(55.0, 75.0)
	_banner("FORTIFIED ZONE", "Only the green corridor is safe", C_SAFE)
	_sfx("warning", -6.0)
	_buzz(80)


func _start_battle() -> void:
	mode = Mode.BATTLE
	battle_t = BATTLE_TIME
	gen_mode = Mode.BATTLE
	gen_change = 0
	strike_t = 4.0
	cover_gap = 2
	shield_hp = 100.0
	slots = slots.filter(func(sl): return not sl["war"])
	slots.append({"id": "rail", "energy": 100.0, "war": true})
	sel = slots.size() - 1
	_sfx("warning")
	_banner("WARNING: BATTLEFIELD", "Survive " + str(int(BATTLE_TIME)) + "s. Shield + Thunder Railgun online", C_RED)
	shake += 10.0
	_buzz(250)


func _end_battle() -> void:
	mode = Mode.CRUISE
	stage += 1
	gen_biome = stage % BIOMES.size()
	gen_mode = Mode.CRUISE
	gen_change = 0
	stage_clock = 0.0
	fort_clock = 0.0
	next_fort = randf_range(40.0, 55.0)
	last_bridge_row = rows_c.size() - 20
	next_bridge_row = rows_c.size() + 70
	var bonus := 2000 * stage
	score += bonus
	health = minf(100.0, health + 30.0)
	fuel = max_fuel
	shield_hp = 0.0
	slots = slots.filter(func(sl): return not sl["war"])
	sel = clampi(sel, 0, maxi(slots.size() - 1, 0))
	_sfx("stage_clear")
	_banner("STAGE CLEAR! +" + _fmt(bonus), "Next: " + String(BIOMES[gen_biome]["name"]) + "   +30% life", C_GOLD)
	_buzz(150)


func _update_weapons(dt: float) -> void:
	var pw := _pw()
	fire_t -= dt
	spec_t -= dt
	emp_cd = maxf(emp_cd - dt, 0.0)
	laser_on = false
	var sp := _active()
	var id: String = sp.get("id", "")
	# escorts use energy the whole time they are selected
	if id == "wingmen" or id == "drones":
		_drain(sp, float(SPECIALS[id]["drain"]) * dt)
	if not firing:
		fire_t = maxf(fire_t, 0.0)
		spec_t = maxf(spec_t, 0.0)
		return
	# basic cannon, always available
	if fire_t <= 0.0:
		fire_t = 0.16
		if id != "spread":
			_bullet(px, pw + 34.0, 0.0, false)
			_sfx("cannon", -8.0, 0.08)
	if id == "":
		return
	match id:
		"spread":
			if spec_t <= 0.0:
				spec_t = 0.16
				for a in [-0.3, -0.15, 0.0, 0.15, 0.3]:
					_bullet(px + a * 40.0, pw + 30.0, sin(a) * 1250.0, false)
				_sfx("spread", -6.0, 0.08)
				_drain(sp, SPECIALS[id]["drain"])
		"laser":
			laser_on = true
			_update_laser(dt)
			_drain(sp, float(SPECIALS[id]["drain"]) * dt)
		"homing":
			if spec_t <= 0.0:
				spec_t = 0.45
				missiles.append({"x": px, "w": pw + 10.0, "vx": randf_range(-240.0, 240.0), "vw": speed + 250.0, "target": null, "life": 3.0, "dead": false})
				_sfx("homing", -6.0)
				_drain(sp, SPECIALS[id]["drain"])
		"rockets":
			if spec_t <= 0.0:
				spec_t = 0.6
				rockets.append({"x": px, "w": pw + 30.0, "vw": speed + 900.0, "life": 0.75, "dead": false, "smoke_t": 0.0})
				_sfx("rocket", -4.0)
				_drain(sp, SPECIALS[id]["drain"])
		"wingmen":
			if spec_t <= 0.0:
				spec_t = 0.2
				_bullet(px - 80.0, pw - 10.0, 0.0, true)
				_bullet(px + 80.0, pw - 10.0, 0.0, true)
				_sfx("wing", -9.0, 0.1)
		"drones":
			if spec_t <= 0.0:
				spec_t = 0.25
				var dp: Vector2 = _drone_pos(randi() % 3)
				_bullet(dp.x, _wy(dp.y), 0.0, true)
				_sfx("drone", -10.0, 0.15)
		"emp":
			# only blasts when something is close, so holding fire doesn't waste it
			if emp_cd <= 0.0 and _emp_has_targets():
				emp_cd = 1.2
				_emp_blast()
				_sfx("emp")
				_drain(sp, SPECIALS[id]["drain"])
		"rail":
			if spec_t <= 0.0:
				spec_t = 0.3
				_fire_rail()
				_sfx("rail", -3.0)
				_drain(sp, SPECIALS[id]["drain"])


func _bullet(x: float, w: float, vx: float, drone: bool) -> void:
	bullets.append({"x": x, "w": w, "vx": vx, "vw": 1250.0 + speed, "dead": false, "drone": drone})


func _update_enemies(dt: float) -> void:
	lock_level = 0.0
	masked = false
	for e in enemies:
		if e["dead"]:
			continue
		var sy := _sy(e["w"])
		if not e["active"]:
			if e["kind"] == "jet":
				if sy > 120.0:
					e["active"] = true
			elif sy > -120.0:
				e["active"] = true
		var kind: String = e["kind"]
		if e["active"] and (kind == "boat" or kind == "heli" or kind == "ship" or kind == "jet"):
			e["x"] += e["vx"] * dt
			var hw: float = e["size"].x * 0.5
			if kind == "jet":
				if e["x"] < -120.0 - xoff or e["x"] > VW + 120.0 + xoff:
					e["dead"] = true
			else:
				var span := _water_span(_row_of(e["w"]))
				if e["x"] - hw < span.x:
					e["x"] = span.x + hw
					e["vx"] = absf(e["vx"])
				elif e["x"] + hw > span.y:
					e["x"] = span.y - hw
					e["vx"] = -absf(e["vx"])
		if e["active"]:
			if kind == "sam":
				_sam_update(e, sy, dt)
			else:
				_enemy_fire(e, sy, dt)
		e["flash"] = maxf(e["flash"] - dt, 0.0)
	for d in depots:
		d["flash"] = maxf(d["flash"] - dt, 0.0)
	for b in bridges:
		b["hit"] = maxf(b["hit"] - dt, 0.0)


func _enemy_fire(e: Dictionary, sy: float, dt: float) -> void:
	var kind: String = e["kind"]
	var imin := 0.0
	var imax := 0.0
	var burst_n := 1
	var gap := 0.1
	var shot := "bullet"
	var dmg := BULLET_DMG
	match kind:
		"heli":
			imin = 1.4
			imax = 2.0
			burst_n = 3
			gap = 0.13
		"ship":
			imin = 1.9
			imax = 2.5
			shot = "shell"
			dmg = SHELL_DMG
		"tank":
			imin = 1.7
			imax = 2.3
			shot = "shell"
			dmg = SHELL_DMG
		"aa":
			imin = 1.5
			imax = 2.1
			burst_n = 4
			gap = 0.08
			shot = "flak"
			dmg = FLAK_DMG
		"soldiers":
			imin = 0.9
			imax = 1.5
		"battery":
			imin = 0.55
			imax = 0.8
			burst_n = 5
			gap = 0.07
			shot = "flak"
			dmg = BATTERY_DMG
		_:
			return
	if sy < 30.0 or sy > vh - 40.0:
		return
	var any_dir := kind == "aa" or kind == "battery"
	if not any_dir and sy > plane_y - 60.0:
		return
	if kind == "battery" and not out_corridor:
		e["burst"] = 0
		return
	if e["burst"] > 0:
		e["burst_t"] -= dt
		if e["burst_t"] <= 0.0:
			e["burst"] -= 1
			e["burst_t"] = gap
			_eshot(e["x"], sy + 6.0, shot, dmg, any_dir)
		return
	e["fire_t"] -= dt
	if e["fire_t"] > 0.0:
		return
	e["fire_t"] = randf_range(imin, imax) / (1.0 + 0.12 * float(stage))
	if burst_n > 1:
		e["burst"] = burst_n
		e["burst_t"] = 0.0
	else:
		_eshot(e["x"], sy + 6.0, shot, dmg, any_dir)


func _eshot(x: float, sy: float, kind: String, dmg: float, any_dir: bool) -> void:
	# aimed at where the jet IS (no leading) and flying straight, so a sidestep dodges it
	var spd := 400.0
	if kind == "shell":
		spd = 290.0
	elif kind == "flak":
		spd = 470.0
	spd += 12.0 * float(stage)
	var from := Vector2(x, sy)
	var target := Vector2(px, plane_y)
	var dir := (target - from).normalized()
	if not any_dir and dir.y < 0.2:
		return
	dir = dir.rotated(randf_range(-0.09, 0.09))
	eshots.append({"x": x, "sy": sy, "vx": dir.x * spd, "vy": dir.y * spd, "kind": kind, "dmg": dmg, "dead": false})


func _sam_update(e: Dictionary, sy: float, dt: float) -> void:
	if sy < -40.0 or sy > vh - 40.0:
		e["lock"] = 0.0
		return
	if e["cool"] > 0.0:
		e["cool"] -= dt
		e["lock"] = maxf(e["lock"] - dt * 2.0, 0.0)
		return
	var from := Vector2(e["x"], sy - 12.0)
	var to := Vector2(px, plane_y)
	var clear := _los_clear(from, to)
	e["masked"] = not clear
	var lt := maxf(LOCK_TIME - 0.1 * float(stage), 1.0)
	if clear:
		e["lock"] += dt
	else:
		e["lock"] = maxf(e["lock"] - dt * 1.5, 0.0)
		masked = true
	lock_level = maxf(lock_level, e["lock"] / lt)
	if e["lock"] >= lt:
		e["lock"] = 0.0
		e["cool"] = randf_range(2.8, 4.2)
		var dir := (to - from).normalized()
		emissiles.append({"x": from.x, "sy": from.y, "vx": dir.x * 220.0, "vy": dir.y * 220.0,
			"spd": 320.0 + 15.0 * float(stage), "life": 4.5, "decoy": null, "dead": false, "smoke_t": 0.0})
		_flash(e["x"], e["w"], 40.0)
		_buzz(60)


func _los_clear(a: Vector2, b: Vector2) -> bool:
	for c in covers:
		var r := _ent_rect(c)
		# the spire is tall, so it also blocks a little above its base
		r = Rect2(r.position.x - 4.0, r.position.y - 44.0, r.size.x + 8.0, r.size.y + 48.0)
		if _seg_hits_rect(a, b, r):
			return false
	return true


func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	if Geometry2D.segment_intersects_segment(a, b, p0, p1) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, p1, p2) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, p2, p3) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, p3, p0) != null:
		return true
	return false


func _update_eshots(dt: float) -> void:
	var pc := Vector2(px, plane_y)
	for s in eshots:
		s["x"] += s["vx"] * dt
		s["sy"] += s["vy"] * dt
		if s["sy"] > vh + 40.0 or s["sy"] < -60.0 or s["x"] < -60.0 - xoff or s["x"] > VW + 60.0 + xoff:
			s["dead"] = true
			continue
		var big: bool = s["kind"] == "shell"
		var hit_r := 28.0 if big else 20.0
		var sp := _active()
		var sid: String = sp.get("id", "")
		var spos := Vector2(s["x"], s["sy"])
		if sid == "drones":
			var blocked := false
			for i in 3:
				if spos.distance_to(_drone_pos(i)) < 18.0:
					blocked = true
			if blocked:
				s["dead"] = true
				_drain(sp, 4.0)
				continue
		elif sid == "wingmen":
			if spos.distance_to(pc + Vector2(-80.0, 26.0)) < 22.0 or spos.distance_to(pc + Vector2(80.0, 26.0)) < 22.0:
				s["dead"] = true
				_drain(sp, 8.0 if big else 3.0)
				continue
		if invuln <= 0.0 and spos.distance_to(pc) < hit_r:
			s["dead"] = true
			var w := _wy(s["sy"])
			_burst(s["x"], w, [Color("#ffb347"), Color.WHITE], 12 if big else 5, 0.5)
			if big:
				_flash(s["x"], w, 36.0)
			_damage(s["dmg"])
			if state != State.PLAY:
				return
	eshots = eshots.filter(func(s): return not s["dead"])


func _update_emissiles(dt: float) -> void:
	var pc := Vector2(px, plane_y)
	var threat := false
	for m in emissiles:
		m["life"] -= dt
		var pos := Vector2(m["x"], m["sy"])
		var tgt := pc
		var dec = m["decoy"]
		var lethal: bool = m.get("lethal", false)
		if lethal and not over_land and not m["lost"]:
			# back over the river in time: the ground missile loses its lock
			m["lost"] = true
			m["life"] = minf(m["life"], 0.45)
			_popup("MISSILE LOST LOCK", px, plane_y - 100.0, 3.0, C_CYAN)
		if dec != null:
			var dp := Vector2(dec["x"], dec["sy"])
			if dec["life"] <= 0.0 or pos.distance_to(dp) < 24.0:
				_missile_pop(m, false)
				continue
			tgt = dp
		var spd: float = m["spd"]
		var v := Vector2(m["vx"], m["vy"])
		if lethal:
			if not m["lost"]:
				v = v.lerp((tgt - pos).normalized() * spd, clampf(dt * 7.0, 0.0, 1.0)).normalized() * minf(v.length() + 1500.0 * dt, spd)
		elif not m.get("dumb", false):
			# guided, but turns slowly and loses track after a sharp dodge
			var want := tgt - pos
			if dec == null and pos.distance_to(pc) < 260.0 and absf(v.angle_to(want)) > 1.0:
				m["dumb"] = true
			v = v.lerp(want.normalized() * spd, clampf(dt * 1.3, 0.0, 1.0)).normalized() * minf(v.length() + 400.0 * dt, spd)
		m["vx"] = v.x
		m["vy"] = v.y
		m["x"] += v.x * dt
		m["sy"] += v.y * dt
		m["smoke_t"] -= dt
		if m["smoke_t"] <= 0.0:
			m["smoke_t"] = 0.035
			smoke.append({"x": m["x"] - v.x * 0.03, "w": _wy(m["sy"] - v.y * 0.03), "r": randf_range(6.0, 10.0), "life": 0.7, "max": 0.7})
		if m["life"] <= 0.0:
			_missile_pop(m, false)
			continue
		var d := Vector2(m["x"], m["sy"]).distance_to(pc)
		if lethal:
			if not m["lost"] and d < 30.0:
				_missile_pop(m, true)
				_flash(px, _pw(), 120.0)
				if shield_hp > 0.0:
					shield_hp = 0.0
					invuln = 1.0
					land_fired = false
					land_t = _land_limit() * 0.5
					_popup("SHIELD SAVED YOU!", px, plane_y - 100.0, 4.0, C_CYAN)
					continue
				_die("SHOT DOWN OVER LAND")
				if state != State.PLAY:
					return
			continue
		if dec == null and _active().get("id", "") == "drones":
			var hitd := false
			for i in 3:
				if Vector2(m["x"], m["sy"]).distance_to(_drone_pos(i)) < 22.0:
					hitd = true
			if hitd:
				_missile_pop(m, false)
				_drain(_active(), 12.0)
				continue
		if dec == null:
			if invuln <= 0.0 and d < 26.0:
				_missile_pop(m, true)
				_damage(SAM_DMG)
				if state != State.PLAY:
					return
				continue
			if d < 210.0:
				threat = true
	if threat and flares > 0 and flare_cd <= 0.0:
		_deploy_flares()
	emissiles = emissiles.filter(func(m): return not m["dead"])


func _land_limit() -> float:
	return maxf(LAND_TIME - 0.1 * float(stage), 2.0)


func _launch_land_missile() -> void:
	# fired from the nearest screen edge (the bank side), very fast, ignores flares
	var sx := -30.0 if px < VW * 0.5 else VW + 30.0
	var from := Vector2(sx, clampf(plane_y - 220.0, 40.0, vh - 260.0))
	var dir := (Vector2(px, plane_y) - from).normalized()
	emissiles.append({"x": from.x, "sy": from.y, "vx": dir.x * 500.0, "vy": dir.y * 500.0,
		"spd": 1000.0, "life": 3.0, "decoy": null, "dead": false, "smoke_t": 0.0,
		"lethal": true, "lost": false})
	_popup("GROUND MISSILE!", px, plane_y - 100.0, 4.0, C_RED)
	_sfx("alarm")
	shake += 4.0
	_buzz(120)


func _missile_pop(m: Dictionary, big: bool) -> void:
	m["dead"] = true
	_sfx("explode", -2.0 if big else -8.0)
	var w := _wy(m["sy"])
	_burst(m["x"], w, [Color("#ffb347"), Color("#ff5a1f"), Color("#e5e7eb")], 14 if big else 8, 0.7)
	_flash(m["x"], w, 60.0 if big else 34.0)


func _deploy_flares() -> void:
	flares -= 1
	flare_cd = 0.6
	var pts: Array = []
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var f := {"x": px, "sy": plane_y + 10.0, "vx": side * randf_range(140.0, 330.0), "vy": randf_range(40.0, 220.0), "life": 1.4}
		flare_fx.append(f)
		pts.append(f)
	for m in emissiles:
		if m["decoy"] == null and not m.get("lethal", false) and Vector2(m["x"], m["sy"]).distance_to(Vector2(px, plane_y)) < 420.0:
			m["decoy"] = pts[randi() % pts.size()]
	_popup("FLARES!", px, plane_y - 84.0, 3.5, C_CYAN)
	_sfx("flare")
	_buzz(40)


func _update_defense(dt: float) -> void:
	var fmax: int = FLARES_MAX
	if flares < fmax:
		flare_rc += dt
		if flare_rc >= FLARE_RECHARGE:
			flare_rc = 0.0
			flares += 1
	else:
		flare_rc = 0.0
	flare_cd = maxf(flare_cd - dt, 0.0)


func _update_strikes(dt: float) -> void:
	var pw := _pw()
	for s in strikes:
		s["t"] -= dt
		if s["t"] <= 0.0:
			_flash(s["x"], s["w"], 95.0)
			_sfx("explode", -4.0)
			_burst(s["x"], s["w"], [Color("#ffb347"), Color("#ff5a1f"), Color("#4b4b4b"), Color.WHITE], 16, 1.0)
			shake += 5.0
			if invuln <= 0.0 and Vector2(px - s["x"], pw - s["w"]).length() < 80.0:
				_damage(STRIKE_DMG)
				if state != State.PLAY:
					return
	strikes = strikes.filter(func(s): return s["t"] > 0.0)


func _damage(amount: float) -> void:
	if god:
		return
	var a := amount * (1.0 + 0.08 * float(stage))
	if shield_hp > 0.0:
		var absorb := minf(shield_hp, a)
		shield_hp -= absorb
		a -= absorb
		shield_fx = 0.3
		_sfx("shield")
		if shield_hp <= 0.0:
			_popup("SHIELD DOWN!", px, plane_y - 110.0, 3.5, C_CYAN)
		if a <= 0.0:
			return
	health -= a
	hurt_t = 0.25
	_sfx("hurt")
	shake += 3.0 + a * 0.4
	_buzz(int(20.0 + a * 4.0))
	if a >= 2.0:
		_popup("-" + str(int(round(a))) + "%", px + 40.0, plane_y - 70.0, 3.5, C_RED)
	if health <= 0.0:
		health = 0.0
		_die("YOUR JET WAS SHOT DOWN")


func _update_shots(dt: float) -> void:
	var top := dist + anchor_y + 40.0
	for b in bullets:
		b["x"] += b["vx"] * dt
		b["w"] += b["vw"] * dt
		if b["w"] > top:
			b["dead"] = true
			continue
		var bsy := _sy(b["w"])
		for m in emissiles:
			if not m["dead"] and Vector2(m["x"], m["sy"]).distance_to(Vector2(b["x"], bsy)) < 22.0:
				_missile_pop(m, false)
				score += 50
				b["dead"] = true
				break
		if not b["dead"] and _hit_test(b["x"], b["w"], 1):
			b["dead"] = true
	bullets = bullets.filter(func(b): return not b["dead"])

	for m in missiles:
		m["life"] -= dt
		var tgt = m["target"]
		if tgt == null or tgt["dead"]:
			m["target"] = _nearest_enemy(m["x"], m["w"])
			tgt = m["target"]
		var aim := Vector2(m["x"], m["w"] + 600.0)
		if tgt != null:
			aim = Vector2(tgt["x"], tgt["w"])
		var dir := (aim - Vector2(m["x"], m["w"])).normalized()
		var rel := Vector2(m["vx"], m["vw"] - speed)
		rel = rel.lerp(dir * 950.0, clampf(dt * 5.0, 0.0, 1.0))
		m["vx"] = rel.x
		m["vw"] = rel.y + speed
		m["x"] += m["vx"] * dt
		m["w"] += m["vw"] * dt
		if m["life"] <= 0.0 or m["w"] > top:
			m["dead"] = true
		elif _hit_test(m["x"], m["w"], 3):
			m["dead"] = true
			_burst(m["x"], m["w"], [Color("#ffd166"), Color("#ff8c1a")], 8, 0.6)
			_flash(m["x"], m["w"], 40.0)
	missiles = missiles.filter(func(m): return not m["dead"])


func _nearest_enemy(x: float, w: float):
	var best_e = null
	var best_d := INF
	for e in enemies:
		if e["dead"] or not e["active"]:
			continue
		var sy := _sy(e["w"])
		if sy < 0.0 or sy > plane_y:
			continue
		var d := Vector2(e["x"] - x, e["w"] - w).length()
		if d < best_d:
			best_d = d
			best_e = e
	return best_e


func _hit_test(x: float, w: float, dmg: int) -> bool:
	var p := Vector2(x, _sy(w))
	for c in covers:
		if _ent_rect(c).has_point(p):
			return true
	for e in enemies:
		if e["dead"] or not e["active"]:
			continue
		if _ent_rect(e).grow(4.0).has_point(p):
			e["hp"] -= dmg
			e["flash"] = 0.08
			if e["hp"] <= 0:
				_kill_enemy(e)
			return true
	for d in depots:
		if d["dead"]:
			continue
		if _ent_rect(d).has_point(p):
			d["hp"] -= dmg
			d["flash"] = 0.08
			if d["hp"] <= 0:
				d["dead"] = true
				score += 80
				_burst(d["x"], d["w"], [Color("#ff4d5e"), Color("#ffffff"), Color("#c8102e")], 18, 1.0)
				_flash(d["x"], d["w"], 70.0)
				_popup("FUEL LOST", d["x"], _sy(d["w"]) - 50.0, 3.5, C_RED)
				shake += 5.0
				_buzz(25)
			return true
	for b in bridges:
		if b["alive"] and w >= b["w"] - 18.0 and w <= b["w"] + 30.0:
			b["hp"] -= dmg
			b["hit"] = 0.08
			if b["hp"] <= 0:
				_destroy_bridge(b)
			return true
	return false


func _kill_enemy(e: Dictionary) -> void:
	if e["dead"]:
		return
	e["dead"] = true
	kills += 1
	var pts: int = e["pts"]
	score += pts
	_add_supply(float(pts))
	var cols := [Color("#ff7a45"), Color("#ffe0c2"), Color("#ffb347")]
	var big := 64.0
	match e["kind"]:
		"heli":
			cols = [Color("#e5484d"), Color("#9fd6ff"), Color("#2b2f36")]
		"jet":
			cols = [Color("#b8c0cc"), Color("#e5484d"), Color("#ffd166")]
		"ship":
			cols = [Color("#8b95a5"), Color("#e9edf2"), Color("#e5484d"), Color("#ffb347")]
		"tank", "aa", "truck", "soldiers", "sam":
			var B: Dictionary = BIOMES[_biome_at(e["w"])]
			cols = [B["camo"], B["camo2"], Color("#2b2f36"), Color("#ffb347")]
			if e["kind"] == "sam":
				big = 100.0
		"battery":
			cols = [Color("#9aa3ae"), Color("#b91c1c"), Color("#ffb347"), Color.WHITE]
			big = 90.0
	_burst(e["x"], e["w"], cols, 18, 1.0)
	_flash(e["x"], e["w"], big)
	_sfx("explode_big" if big > 80.0 else "explode", -2.0)
	_spawn_coins(e["x"], e["w"], 3)
	_popup("+" + str(pts), e["x"], _sy(e["w"]) - 44.0, 4.0, C_GOLD)
	shake += 4.0
	_buzz(25)


func _destroy_bridge(b: Dictionary) -> void:
	if not b["alive"]:
		return
	b["alive"] = false
	bridges_down += 1
	for e in enemies:
		if e["kind"] == "tank" and not e["dead"] and absf(e["w"] - b["w"]) < 5.0:
			_kill_enemy(e)
	score += 500
	_add_supply(500.0)
	fuel = minf(max_fuel, fuel + 25.0)
	var cols := [Color("#c9a27a"), Color("#a77d55"), Color("#ffb347"), Color("#ffd166"), Color("#e3c39d")]
	for i in 7:
		_burst(randf_range(40.0, VW - 40.0), b["w"], cols, 10, 1.2)
	_burst(px, b["w"], cols, 22, 1.7)
	_flash(px, b["w"], 150.0)
	_flash(clampf(px - 200.0, 60.0, VW - 60.0), b["w"], 80.0)
	_flash(clampf(px + 200.0, 60.0, VW - 60.0), b["w"], 80.0)
	_sfx("explode_big")
	popups.append({"text": "BRIDGE DOWN! +500", "x": VW * 0.5, "sy": _sy(b["w"]) + 70.0, "life": 1.4, "px": 4.0, "col": C_INK, "badge": true})
	shake += 18.0
	_buzz(120)


func _die(reason: String) -> void:
	if god and reason != "OUT OF FUEL":
		invuln = 1.0
		return
	state = State.DEAD
	death_reason = reason
	_sfx("explode_big")
	_sfx("gameover", -3.0)
	dead_t = 0.0
	touching = false
	var pw := _pw()
	_burst(px, pw, [Color("#8793a3"), Color("#ff8c1a"), Color("#ffffff"), Color("#4b5563")], 34, 1.6)
	_flash(px, pw, 120.0)
	shake += 24.0
	_buzz(220)
	if int(score) > best:
		best = int(score)
		_save_best()


# ---------------------------------------------------------------- special weapons

func _active() -> Dictionary:
	if slots.is_empty():
		return {}
	sel = clampi(sel, 0, slots.size() - 1)
	return slots[sel]


func _drain(sp: Dictionary, amount: float) -> void:
	if sp.is_empty():
		return
	sp["energy"] -= amount
	if sp["energy"] <= 0.0:
		var i := slots.find(sp)
		if i >= 0:
			slots.remove_at(i)
			if sel >= i and sel > 0:
				sel -= 1
		toasts.append({"text": String(SPECIALS[sp["id"]]["name"]) + " USED UP", "life": 2.0})


func _pickup_weapon(id: String) -> void:
	weapons_got += 1
	var nm: String = SPECIALS[id]["name"]
	_sfx("weapon")
	_buzz(50)
	for i in slots.size():
		if slots[i]["id"] == id:
			slots[i]["energy"] = 100.0
			sel = i
			toasts.append({"text": nm + " REFILLED", "life": 2.2})
			return
	var normal := 0
	for sl in slots:
		if not sl["war"]:
			normal += 1
	var item := {"id": id, "energy": 100.0, "war": false}
	if normal < 2:
		slots.insert(normal, item)
		sel = normal
		toasts.append({"text": "NEW WEAPON: " + nm, "life": 2.4})
	else:
		# both slots full: drop the one with the least energy
		var wi := 1 if slots[1]["energy"] < slots[0]["energy"] else 0
		var old: String = SPECIALS[slots[wi]["id"]]["name"]
		slots[wi] = item
		sel = wi
		toasts.append({"text": nm + " | DROPPED " + old, "life": 2.6})


func _select_slot(i: int) -> void:
	if i >= 0 and i < slots.size() and i != sel:
		sel = i
		_sfx("tap")
		_popup(String(SPECIALS[slots[i]["id"]]["name"]), px, plane_y - 90.0, 3.0, SPECIALS[slots[i]["id"]]["col"])
		_buzz(20)


func _drone_pos(i: int) -> Vector2:
	var a := t * 2.4 + float(i) * TAU / 3.0
	return Vector2(px + cos(a) * 70.0, plane_y + sin(a) * 70.0)


func _damage_enemy(e: Dictionary, dmg: int) -> void:
	if e["dead"] or not e["active"]:
		return
	e["hp"] -= dmg
	e["flash"] = 0.08
	if e["hp"] <= 0:
		_kill_enemy(e)


func _damage_depot(d: Dictionary, dmg: int) -> void:
	if d["dead"]:
		return
	d["hp"] -= dmg
	d["flash"] = 0.08
	if d["hp"] <= 0:
		d["dead"] = true
		score += 80
		_burst(d["x"], d["w"], [Color("#ff4d5e"), Color("#ffffff"), Color("#c8102e")], 18, 1.0)
		_flash(d["x"], d["w"], 70.0)
		_popup("FUEL LOST", d["x"], _sy(d["w"]) - 50.0, 3.5, C_RED)
		shake += 5.0


func _damage_bridge(b: Dictionary, dmg: int) -> void:
	if not b["alive"]:
		return
	b["hp"] -= dmg
	b["hit"] = 0.08
	if b["hp"] <= 0:
		_destroy_bridge(b)


func _update_laser(dt: float) -> void:
	# the beam stops at the first rock spire in front of the jet
	var top := -20.0
	for c in covers:
		var r := _ent_rect(c)
		if r.position.x < px + 8.0 and r.end.x > px - 8.0 and r.end.y < plane_y - 20.0:
			top = maxf(top, r.end.y - 30.0)
	laser_top = top
	laser_tick -= dt
	if laser_tick > 0.0:
		return
	laser_tick = 0.08
	var beam := Rect2(px - 10.0, top, 20.0, plane_y - 30.0 - top)
	for e in enemies:
		if e["active"] and not e["dead"] and _ent_rect(e).intersects(beam):
			_damage_enemy(e, 1)
	for d in depots:
		if not d["dead"] and _ent_rect(d).intersects(beam):
			_damage_depot(d, 1)
	for b in bridges:
		var bsy := _sy(b["w"])
		if b["alive"] and bsy > top and bsy < plane_y:
			_damage_bridge(b, 1)
	for m in emissiles:
		if not m["dead"] and not m.get("lethal", false) and beam.has_point(Vector2(m["x"], m["sy"])):
			_missile_pop(m, false)


func _fire_rail() -> void:
	# piercing shot: hits everything in a column in front of the jet
	rail_fx = 0.15
	rail_x = px
	var beam := Rect2(px - 18.0, -40.0, 36.0, plane_y)
	for e in enemies:
		if e["active"] and not e["dead"] and _ent_rect(e).intersects(beam):
			_damage_enemy(e, 6)
	for b in bridges:
		var bsy := _sy(b["w"])
		if b["alive"] and bsy > 0.0 and bsy < plane_y:
			_damage_bridge(b, 6)
	for m in emissiles:
		if not m["dead"] and not m.get("lethal", false) and beam.has_point(Vector2(m["x"], m["sy"])):
			_missile_pop(m, false)
	for es in eshots:
		if beam.has_point(Vector2(es["x"], es["sy"])):
			es["dead"] = true
	shake += 2.0
	_buzz(15)


func _emp_has_targets() -> bool:
	var pc := Vector2(px, plane_y)
	for es in eshots:
		if Vector2(es["x"], es["sy"]).distance_to(pc) < 300.0:
			return true
	for m in emissiles:
		if not m.get("lethal", false) and Vector2(m["x"], m["sy"]).distance_to(pc) < 420.0:
			return true
	for e in enemies:
		if e["active"] and not e["dead"] and Vector2(e["x"], _sy(e["w"])).distance_to(pc) < 300.0:
			return true
	return false


func _emp_blast() -> void:
	emp_fx = 0.5
	var pc := Vector2(px, plane_y)
	for es in eshots:
		if Vector2(es["x"], es["sy"]).distance_to(pc) < 420.0:
			es["dead"] = true
	for m in emissiles:
		if not m["dead"] and not m.get("lethal", false) and Vector2(m["x"], m["sy"]).distance_to(pc) < 420.0:
			_missile_pop(m, false)
	for e in enemies:
		if e["active"] and not e["dead"] and Vector2(e["x"], _sy(e["w"])).distance_to(pc) < 360.0:
			_damage_enemy(e, 3)
	shake += 6.0
	_buzz(80)


func _update_rockets(dt: float) -> void:
	var top := dist + anchor_y + 40.0
	for r in rockets:
		r["w"] += r["vw"] * dt
		r["life"] -= dt
		r["smoke_t"] -= dt
		if r["smoke_t"] <= 0.0:
			r["smoke_t"] = 0.03
			smoke.append({"x": r["x"] + randf_range(-3.0, 3.0), "w": r["w"] - 20.0, "r": randf_range(5.0, 8.0), "life": 0.5, "max": 0.5})
		var p := Vector2(r["x"], _sy(r["w"]))
		var boom: bool = r["life"] <= 0.0 or r["w"] > top
		if not boom:
			for c in covers:
				if _ent_rect(c).has_point(p):
					boom = true
					break
		if not boom:
			for e in enemies:
				if e["active"] and not e["dead"] and _ent_rect(e).grow(6.0).has_point(p):
					boom = true
					break
		if not boom:
			for b in bridges:
				if b["alive"] and absf(r["w"] - b["w"]) < 24.0:
					boom = true
					break
		if boom:
			r["dead"] = true
			_rocket_boom(r["x"], r["w"])
	rockets = rockets.filter(func(r): return not r["dead"])


func _rocket_boom(x: float, w: float) -> void:
	_flash(x, w, 95.0)
	_sfx("explode", -3.0)
	_burst(x, w, [Color("#ffb347"), Color("#ff5a1f"), Color("#ffd166"), Color.WHITE], 16, 1.0)
	shake += 4.0
	for e in enemies:
		if e["active"] and not e["dead"] and Vector2(e["x"] - x, e["w"] - w).length() < 95.0:
			_damage_enemy(e, 4)
	for d in depots:
		if not d["dead"] and Vector2(d["x"] - x, d["w"] - w).length() < 80.0:
			_damage_depot(d, 4)
	for b in bridges:
		if b["alive"] and absf(b["w"] - w) < 60.0:
			_damage_bridge(b, 4)


func _banner(title: String, sub: String, col: Color) -> void:
	banner = {"title": title, "sub": sub, "col": col, "life": 3.2}


func _biome_at(w: float) -> int:
	return rows_b[_row_of(w)]


# ---------------------------------------------------------------- effects

func _burst(x: float, w: float, cols: Array, n: int, power: float) -> void:
	for i in n:
		if debris.size() > 450:
			return
		var a := randf() * TAU
		var s := randf_range(80.0, 400.0) * power
		var life := randf_range(0.5, 1.1)
		debris.append({
			"x": x, "w": w, "vx": cos(a) * s, "vw": sin(a) * s,
			"life": life, "max": life, "col": cols[randi() % cols.size()], "s": randf_range(8.0, 20.0),
			"rot": randf() * TAU, "vr": randf_range(-8.0, 8.0),
		})


func _flash(x: float, w: float, r: float) -> void:
	flashes.append({"x": x, "w": w, "r": r, "life": 0.35, "max": 0.35})


func _spawn_coins(x: float, w: float, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		coin_fx.append({"x": x, "w": w, "vx": cos(a) * 220.0, "vw": sin(a) * 220.0, "age": 0.0})


func _popup(text: String, x: float, sy: float, pxs: float, col: Color) -> void:
	popups.append({"text": text, "x": x, "sy": sy, "life": 1.1, "px": pxs, "col": col, "badge": false})


func _update_fx(dt: float) -> void:
	for p in debris:
		p["x"] += p["vx"] * dt
		p["w"] += p["vw"] * dt
		var damp := clampf(1.0 - dt * 3.0, 0.0, 1.0)
		p["vx"] *= damp
		p["vw"] *= damp
		p["rot"] += p["vr"] * dt
		p["life"] -= dt
	debris = debris.filter(func(p): return p["life"] > 0.0)

	for s in smoke:
		s["life"] -= dt
		s["r"] += 14.0 * dt
	smoke = smoke.filter(func(s): return s["life"] > 0.0)

	for f in flashes:
		f["life"] -= dt
	flashes = flashes.filter(func(f): return f["life"] > 0.0)

	for f in flare_fx:
		f["x"] += f["vx"] * dt
		f["sy"] += f["vy"] * dt
		f["vx"] *= clampf(1.0 - dt * 1.5, 0.0, 1.0)
		f["vy"] += 160.0 * dt
		f["life"] -= dt
	flare_fx = flare_fx.filter(func(f): return f["life"] > 0.0)

	var pw := _pw()
	for c in coin_fx:
		c["age"] += dt
		if c["age"] < 0.25 or state != State.PLAY:
			c["x"] += c["vx"] * dt
			c["w"] += c["vw"] * dt
		else:
			var to := Vector2(px - c["x"], pw - c["w"])
			if to.length() < 34.0:
				c["age"] = -1.0
				coins += 1
				continue
			var v := to.normalized() * minf(1800.0, 400.0 + c["age"] * 2400.0)
			c["x"] += v.x * dt
			c["w"] += v.y * dt + speed * dt
	coin_fx = coin_fx.filter(func(c): return c["age"] >= 0.0 and c["age"] < 3.0)

	for p in popups:
		p["sy"] -= 50.0 * dt
		p["life"] -= dt
	popups = popups.filter(func(p): return p["life"] > 0.0)

	rail_fx = maxf(rail_fx - dt, 0.0)
	emp_fx = maxf(emp_fx - dt, 0.0)
	shield_fx = maxf(shield_fx - dt, 0.0)
	if not banner.is_empty():
		banner["life"] -= dt
		if banner["life"] <= 0.0:
			banner = {}
	if not toasts.is_empty():
		toasts[0]["life"] -= dt
		if toasts[0]["life"] <= 0.0:
			toasts.pop_front()


func _buzz(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position - Vector2(xoff, 0.0)
		if event.pressed and state == State.PLAY:
			if picking:
				var pi := _pick_at(pos)
				if pi >= 0:
					_pick_choose(pi)
					return
			elif supply_ready and _supply_rect().grow(8.0).has_point(pos):
				_open_picker()
				return
			var si := _slot_at(pos)
			if si >= 0:
				_select_slot(si)
				return
		if event.index != 0:
			return
		if event.pressed:
			touching = true
			_on_tap(pos)
		else:
			touching = false
	elif event is InputEventScreenDrag:
		if event.index != 0:
			return
		if state == State.PLAY and not picking:
			px = clampf(px + event.relative.x * STEER_SENS, 20.0 - xoff, VW - 20.0 + xoff)
			plane_y = clampf(plane_y + event.relative.y * STEER_SENS, _ymin(), _ymax())
	elif event is InputEventJoypadButton:
		if event.pressed:
			_pad_button(event.button_index)
	elif event is InputEventKey:
		var key: Key = event.keycode
		var is_ok := key == KEY_ENTER or key == KEY_KP_ENTER
		if not event.pressed:
			if is_ok and enter_down:
				enter_down = false
				if not enter_long and state == State.PLAY and not picking:
					fire_latch = not fire_latch
					_popup("AUTO FIRE " + ("ON" if fire_latch else "OFF"), px, plane_y - 110.0, 3.5, C_GOLD)
			return
		if event.echo:
			return
		if key == KEY_BACK:
			_back()
			return
		if state == State.PAUSED:
			_menu_key(event)
			return
		if state == State.PLAY and picking:
			if event.is_action_pressed("ui_left"):
				pick_focus = posmod(pick_focus - 1, unlocked)
			elif event.is_action_pressed("ui_right"):
				pick_focus = posmod(pick_focus + 1, unlocked)
			elif is_ok or key == KEY_SPACE or key == KEY_E:
				_pick_choose(pick_focus)
			elif key == KEY_ESCAPE:
				picking = false
			return
		if is_ok:
			if state == State.PLAY:
				enter_down = true
				enter_t = t
				enter_long = false
			else:
				_on_tap(Vector2(-1000.0, -1000.0))
			return
		if key == KEY_SPACE:
			if state != State.PLAY:
				_on_tap(Vector2(-1000.0, -1000.0))
		elif key == KEY_P or key == KEY_ESCAPE:
			_pause()
		elif state == State.PLAY and (key == KEY_Q or key == KEY_TAB):
			if slots.size() > 1:
				_select_slot((sel + 1) % slots.size())
		elif state == State.PLAY and key == KEY_E:
			_open_picker()
		elif state == State.PLAY and key >= KEY_1 and key <= KEY_3:
			_select_slot(int(key - KEY_1))
		elif state == State.PLAY and OS.is_debug_build():
			match key:
				KEY_B:
					_debug_skip_to_bridge()
				KEY_F:
					_test_action("fort")
				KEY_N:
					_test_action("battle")
				KEY_M:
					_test_action("endbattle")
				KEY_K:
					_test_action("scenery")
				KEY_J:
					_pickup_weapon(CRATE_POOL[randi() % CRATE_POOL.size()])
				KEY_H:
					_test_action("supply")
				KEY_G:
					_test_action("god")


func _pad_button(b: int) -> void:
	match state:
		State.TITLE, State.DEAD:
			if b == JOY_BUTTON_A or b == JOY_BUTTON_START:
				_on_tap(Vector2(-1000.0, -1000.0))
		State.PAUSED:
			if b == JOY_BUTTON_A:
				_menu_activate(menu_focus)
			elif b == JOY_BUTTON_B or b == JOY_BUTTON_START:
				state = State.PLAY
			elif b == JOY_BUTTON_DPAD_UP:
				menu_focus = posmod(menu_focus - 1, _menu_items().size())
			elif b == JOY_BUTTON_DPAD_DOWN:
				menu_focus = posmod(menu_focus + 1, _menu_items().size())
		State.PLAY:
			if picking:
				if b == JOY_BUTTON_DPAD_LEFT:
					pick_focus = posmod(pick_focus - 1, unlocked)
				elif b == JOY_BUTTON_DPAD_RIGHT:
					pick_focus = posmod(pick_focus + 1, unlocked)
				elif b == JOY_BUTTON_A or b == JOY_BUTTON_Y:
					_pick_choose(pick_focus)
				elif b == JOY_BUTTON_B:
					picking = false
			elif b == JOY_BUTTON_X or b == JOY_BUTTON_RIGHT_SHOULDER:
				if slots.size() > 1:
					_select_slot((sel + 1) % slots.size())
			elif b == JOY_BUTTON_Y:
				_open_picker()
			elif b == JOY_BUTTON_START or b == JOY_BUTTON_BACK:
				_pause()


func _menu_key(event: InputEventKey) -> void:
	var n := _menu_items().size()
	if event.is_action_pressed("ui_up"):
		menu_focus = posmod(menu_focus - 1, n)
	elif event.is_action_pressed("ui_down"):
		menu_focus = posmod(menu_focus + 1, n)
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
		_menu_activate(menu_focus)
	elif event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
		state = State.PLAY


func _on_tap(pos: Vector2) -> void:
	match state:
		State.TITLE:
			_sfx("tap")
			_start_run()
		State.DEAD:
			if dead_t > 0.7:
				_sfx("tap")
				_start_run()
		State.PAUSED:
			for i in _menu_items().size():
				if _menu_rect(i).has_point(pos):
					menu_focus = i
					_menu_activate(i)
					return
		State.PLAY:
			if _pause_rect().grow(10.0).has_point(pos):
				_pause()


# ---------------------------------------------------------------- pause menu

func _menu_items() -> Array:
	var items: Array = [
		["resume", "RESUME"],
		["music", "MUSIC: " + ("ON" if music_on else "OFF")],
		["sfx", "SOUND FX: " + ("ON" if sfx_on else "OFF")],
	]
	if OS.is_debug_build():
		items.append(["battle", "TEST: BATTLEFIELD NOW"])
		items.append(["fort", "TEST: FORTIFIED ZONE"])
		items.append(["scenery", "TEST: NEXT SCENERY"])
		items.append(["supply", "TEST: SUPPLY READY"])
		items.append(["god", "TEST: GOD MODE " + ("ON" if god else "OFF")])
	items.append(["end", "END RUN"])
	return items


func _menu_rect(i: int) -> Rect2:
	return Rect2(110.0, vh * 0.2 + 120.0 + float(i) * 78.0, VW - 220.0, 64.0)


func _menu_activate(i: int) -> void:
	var items := _menu_items()
	if i < 0 or i >= items.size():
		return
	var id: String = items[i][0]
	_sfx("tap")
	match id:
		"resume":
			state = State.PLAY
		"music":
			music_on = not music_on
			_save_best()
		"sfx":
			sfx_on = not sfx_on
			_save_best()
		"end":
			state = State.TITLE
			if int(score) > best:
				best = int(score)
				_save_best()
		_:
			_test_action(id)
			state = State.PLAY


func _test_action(id: String) -> void:
	# testing shortcuts (debug builds only): pause menu buttons and B/F/N/M/K/H/G keys
	if not OS.is_debug_build():
		return
	match id:
		"battle":
			if mode == Mode.CRUISE:
				stage_clock = STAGE_TIME - 0.5
				if gen_mode == Mode.FORT:
					gen_mode = Mode.CRUISE
		"endbattle":
			if mode == Mode.BATTLE:
				battle_t = 0.1
		"fort":
			if mode == Mode.CRUISE and gen_mode == Mode.CRUISE:
				_start_fort()
		"scenery":
			gen_biome = (gen_biome + 1) % BIOMES.size()
		"supply":
			supply = supply_need
			supply_ready = true
			_sfx("supply_ready")
		"god":
			god = not god
			_popup("GOD MODE " + ("ON" if god else "OFF"), VW * 0.5, plane_y - 120.0, 4.0, C_GOLD)


# ---------------------------------------------------------------- supply picker UI

func _supply_rect() -> Rect2:
	return Rect2(24.0, 184.0, 290.0, 56.0)


func _pick_rect(i: int) -> Rect2:
	var n := maxi(unlocked, 1)
	var w := (VW - 72.0 - 8.0 * float(n - 1)) / float(n)
	return Rect2(36.0 + float(i) * (w + 8.0), _panel_y() - 128.0, w, 96.0)


func _pick_at(pos: Vector2) -> int:
	for i in unlocked:
		if _pick_rect(i).grow(4.0).has_point(pos):
			return i
	return -1


# ---------------------------------------------------------------- audio

func _setup_audio() -> void:
	for nm in ["cannon", "spread", "laser", "homing", "rocket", "rail", "emp", "drone", "wing",
			"explode", "explode_big", "hurt", "fuel", "life", "weapon", "supply_ready", "unlock",
			"flare", "lock", "land_warn", "alarm", "shield", "zap", "tap", "stage_clear", "gameover", "warning"]:
		var path: String = "res://audio/sfx/" + String(nm) + ".wav"
		if ResourceLoader.exists(path):
			snd[nm] = load(path)
	for nm in ["cruise", "fort", "battle"]:
		var path: String = "res://audio/music/" + String(nm) + ".ogg"
		if ResourceLoader.exists(path):
			var st = load(path)
			if st is AudioStreamOggVorbis:
				st.loop = true
			music_tracks[nm] = st
	for i in 14:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		sfx_players.append(pl)
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	add_child(music_a)
	add_child(music_b)
	laser_player = AudioStreamPlayer.new()
	add_child(laser_player)
	if snd.has("laser"):
		var ls := (snd["laser"] as AudioStreamWAV).duplicate() as AudioStreamWAV
		ls.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ls.loop_begin = 0
		ls.loop_end = int(ls.get_length() * float(ls.mix_rate))
		laser_player.stream = ls
		laser_player.volume_db = -10.0


func _sfx(nm: String, vol := 0.0, pitch_var := 0.04) -> void:
	if not sfx_on or not snd.has(nm) or sfx_players.is_empty():
		return
	# don't stack the same sound within a few milliseconds
	var last: float = sfx_last.get(nm, -1.0)
	if t - last < 0.035:
		return
	sfx_last[nm] = t
	var pl: AudioStreamPlayer = sfx_players[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_players.size()
	pl.stream = snd[nm]
	pl.volume_db = vol
	pl.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	pl.play()


func _update_audio(dt: float) -> void:
	# music: cruise / fortified zone / battlefield, cross-faded
	var want := "cruise"
	if state == State.PLAY or state == State.PAUSED:
		var prow := _row_of(_pw())
		if mode == Mode.BATTLE:
			want = "battle"
		elif rows_m[prow] == Mode.FORT or gen_mode == Mode.FORT:
			want = "fort"
	if not music_tracks.has(want):
		want = ""
	if want != music_cur:
		music_cur = want
		var tmp := music_a
		music_a = music_b
		music_b = tmp
		if want != "":
			music_a.stream = music_tracks[want]
			music_a.volume_db = -40.0
			music_a.play()
		music_fade = 0.0
	music_fade = minf(music_fade + dt / 1.2, 1.0)
	var target := -9.0
	if state == State.DEAD or state == State.TITLE:
		target = -14.0
	if state == State.PAUSED:
		target = -20.0
	if not music_on:
		target = -80.0
	if music_a.playing:
		music_a.volume_db = lerpf(-40.0, target, music_fade) if music_fade < 1.0 else target
	if music_b.playing:
		music_b.volume_db = lerpf(target, -60.0, music_fade)
		if music_fade >= 1.0:
			music_b.stop()
	# laser beam hum
	var laser_should := laser_on and state == State.PLAY and sfx_on
	if laser_should and not laser_player.playing and laser_player.stream != null:
		laser_player.play()
	elif not laser_should and laser_player.playing:
		laser_player.stop()
	# warning beeps: missile lock and flying over land
	beep_t -= dt
	if state == State.PLAY and beep_t <= 0.0:
		if over_land and not land_fired:
			var k := clampf(land_t / _land_limit(), 0.0, 1.0)
			_sfx("land_warn", -4.0, 0.0)
			beep_t = lerpf(0.4, 0.1, k)
		elif lock_level > 0.3:
			_sfx("lock", -6.0, 0.0)
			beep_t = lerpf(0.35, 0.08, clampf(lock_level, 0.0, 1.0))


# ---------------------------------------------------------------- self-test (CI)

func _autotest(dt: float) -> void:
	# Runs when started with "-- --autotest": plays through every system quickly
	# and quits, so the cloud build can catch script errors.
	at_t += dt
	var steps := [
		[0.5, "start"], [1.5, "god"], [2.0, "weapons"], [3.0, "supply"], [3.5, "pick"],
		[5.0, "fort"], [14.0, "battle"], [16.0, "pause"], [16.5, "menu_music"], [17.0, "resume"],
		[24.0, "endbattle"], [26.0, "scenery"], [30.0, "scenery"], [34.0, "land"], [38.0, "done"],
	]
	while at_step < steps.size() and at_t >= float(steps[at_step][0]):
		var a: String = steps[at_step][1]
		at_step += 1
		print("AUTOTEST step ", a, " t=", snappedf(at_t, 0.1))
		match a:
			"start":
				_start_run()
			"god":
				god = true
			"weapons":
				for id in SPECIALS.keys():
					_pickup_weapon(id)
				for i in 3:
					_select_slot(i)
			"supply":
				_test_action("supply")
			"pick":
				_open_picker()
				_pick_choose(0)
			"fort":
				_test_action("fort")
			"battle":
				_test_action("battle")
			"pause":
				_pause()
			"menu_music":
				_menu_activate(1)
				_menu_activate(1)
			"resume":
				state = State.PLAY
			"endbattle":
				_test_action("endbattle")
			"scenery":
				_test_action("scenery")
			"land":
				px = -xoff + 30.0
			"done":
				print("AUTOTEST OK score=", int(score), " kills=", kills, " weapons=", weapons_got, " view=", get_viewport_rect().size, " xoff=", xoff)
				get_tree().quit()
	if state == State.PLAY:
		touching = true
		if int(at_t) % 2 == 0 and slots.size() > 1:
			sel = (sel + 1) % slots.size()
		# wiggle the jet so collisions and pickups happen
		if at_step < 13:
			px = 360.0 + sin(at_t * 1.7) * 120.0


func _debug_skip_to_bridge() -> void:
	# Testing shortcut (debug builds only): jump to just before the next bridge.
	if gen_mode != Mode.CRUISE:
		return
	_ensure_rows(next_bridge_row + 2)
	var pw := _pw()
	var target = null
	for b in bridges:
		if b["alive"] and b["w"] > pw + 100.0:
			target = b
			break
	if target == null:
		return
	dist = target["w"] - 900.0 - (anchor_y - plane_y)
	_ensure_rows(int((dist + anchor_y + 200.0) / ROW) + 2)
	var span := _water_span(_row_of(_pw()))
	px = (span.x + span.y) * 0.5
	fuel = max_fuel
	invuln = 1.0
	var low := dist - (vh - anchor_y) - 100.0
	enemies = enemies.filter(func(e): return e["w"] > low)
	depots = depots.filter(func(e): return e["w"] > low)
	kits = kits.filter(func(e): return e["w"] > low)
	eshots.clear()
	emissiles.clear()


func _start_run() -> void:
	_reset()
	state = State.PLAY


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		best = int(cf.get_value("stats", "best", 0))
		music_on = bool(cf.get_value("settings", "music", true))
		sfx_on = bool(cf.get_value("settings", "sfx", true))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("stats", "best", best)
	cf.set_value("settings", "music", music_on)
	cf.set_value("settings", "sfx", sfx_on)
	cf.save("user://save.cfg")


# ---------------------------------------------------------------- drawing helpers

func _plane_rect() -> Rect2:
	return Rect2(px - 26.0, plane_y - 28.0, 52.0, 56.0)


func _hitbox() -> Rect2:
	return Rect2(px - 15.0, plane_y - 20.0, 30.0, 40.0)


func _ent_rect(e: Dictionary) -> Rect2:
	var s: Vector2 = e["size"]
	return Rect2(e["x"] - s.x * 0.5, _sy(e["w"]) - s.y * 0.5, s.x, s.y)


func _panel_y() -> float:
	return vh - 284.0


func _slot_count() -> int:
	return maxi(2, slots.size())


func _slot_rect(i: int) -> Rect2:
	var n := _slot_count()
	var w := (VW - 92.0 - 12.0 * float(n - 1)) / float(n)
	return Rect2(46.0 + float(i) * (w + 12.0), _panel_y() + 144.0, w, 72.0)


func _slot_at(pos: Vector2) -> int:
	for i in _slot_count():
		if _slot_rect(i).grow(6.0).has_point(pos):
			return i
	return -1


func _pause_rect() -> Rect2:
	return Rect2(VW - 108.0, 44.0, 84.0, 84.0)


func _rrect(r: Rect2, col: Color, radius: float, border_col := Color(0, 0, 0, 0), border_w := 0) -> void:
	var key := int(radius) * 100 + border_w
	var sb: StyleBoxFlat = sb_cache.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(int(radius))
		sb.anti_aliasing = true
		sb.set_border_width_all(border_w)
		sb_cache[key] = sb
	sb.bg_color = col
	sb.border_color = border_col
	cv.draw_style_box(sb, r)


func _ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var base := shake_off if cv == self else Vector2.ZERO
	cv.draw_set_transform(base + center, 0.0, Vector2(1.0, ry / rx))
	cv.draw_circle(Vector2.ZERO, rx, col)
	cv.draw_set_transform(base)


func _cube(r: Rect2, depth: float, top: Color, side: Color, edge := true) -> void:
	if depth > 0.0:
		cv.draw_rect(Rect2(r.position.x, r.end.y, r.size.x, depth), side)
	cv.draw_rect(r, top)
	if edge:
		cv.draw_rect(r.grow(-0.5), top.darkened(0.12), false, 1.0)


# Pixel sprite drawn as voxels: dark outline, darker front face, then tops.
# Each look is baked into a texture once and then drawn with a single call.
func _vsprite(rows: Array, center: Vector2, cell: float, cmap: Dictionary, depth: float, flip := false, outline := true, flash := false) -> void:
	var key := [rows, cmap, cell, depth, flip, outline, flash].hash()
	var ent: Array = spr_cache.get(key, [])
	if ent.is_empty():
		ent = _bake_sprite(rows, cell, cmap, depth, flip, outline, flash)
		spr_cache[key] = ent
	var tex: Texture2D = ent[0]
	var k: float = ent[1]
	var cols := String(rows[0]).length()
	var origin := center - Vector2(float(cols) * cell, float(rows.size()) * cell) * 0.5 - Vector2(2.0, 2.0) * k
	cv.draw_texture_rect(tex, Rect2(origin, Vector2(tex.get_width(), tex.get_height()) * k), false)


func _bake_sprite(rows: Array, cell: float, cmap: Dictionary, depth: float, flip: bool, outline: bool, flash: bool) -> Array:
	var ci := maxi(int(ceil(cell)), 1)
	var k := cell / float(ci)
	var db := int(round(depth / k))
	var cols := String(rows[0]).length()
	var w := cols * ci + 4
	var h := rows.size() * ci + db + 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cells: Array = []
	for j in rows.size():
		var line: String = rows[j]
		for i in line.length():
			var ch := line[i]
			if cmap.has(ch):
				var ii := (cols - 1 - i) if flip else i
				var c: Color = Color.WHITE if flash else cmap[ch]
				cells.append([Vector2i(2 + ii * ci, 2 + j * ci), c])
	if outline:
		for cdat in cells:
			var p: Vector2i = cdat[0]
			img.fill_rect(Rect2i(p.x - 2, p.y - 2, ci + 4, ci + db + 4), C_OUTLINE)
	if db > 0:
		for cdat in cells:
			var p: Vector2i = cdat[0]
			var c: Color = cdat[1]
			img.fill_rect(Rect2i(p.x, p.y + ci, ci, db), c.darkened(0.4))
	for cdat in cells:
		var p: Vector2i = cdat[0]
		var c: Color = cdat[1]
		img.fill_rect(Rect2i(p.x, p.y, ci, ci), c)
	return [ImageTexture.create_from_image(img), k]


func _ptext_width(text: String, pxs: float) -> float:
	if text.is_empty():
		return 0.0
	return float(text.length()) * 6.0 * pxs - pxs


# Pixel-font text. align: 0 left, 1 centre, 2 right. pos.y is the top of the letters.
func _ptext(text: String, pos: Vector2, pxs: float, col: Color, align := 0, shadow := Color(0, 0, 0, 0)) -> void:
	var tx := text.to_upper()
	var w := _ptext_width(tx, pxs)
	var x0 := pos.x
	if align == 1:
		x0 -= w * 0.5
	elif align == 2:
		x0 -= w
	if shadow.a > 0.0:
		_ptext_raw(tx, Vector2(x0 + pxs * 0.6, pos.y + pxs), pxs, shadow)
	_ptext_raw(tx, Vector2(x0, pos.y), pxs, col)


func _ptext_raw(tx: String, origin: Vector2, pxs: float, col: Color) -> void:
	# each text string is baked once into a tiny white texture (1 px per font pixel)
	# and drawn scaled and tinted
	if tx.is_empty():
		return
	var tex: Texture2D = txt_cache.get(tx)
	if tex == null:
		if txt_cache.size() > 400:
			txt_cache.clear()
		var w := tx.length() * 6 - 1
		var img := Image.create(w, 7, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for k in tx.length():
			var ch := tx[k]
			if not GLYPHS.has(ch):
				continue
			var g: Array = GLYPHS[ch]
			for j in 7:
				var line: String = g[j]
				for i in 5:
					if line[i] == "#":
						img.set_pixel(k * 6 + i, j, Color.WHITE)
		tex = ImageTexture.create_from_image(img)
		txt_cache[tx] = tex
	cv.draw_texture_rect(tex, Rect2(origin, Vector2(tex.get_width(), 7) * pxs), false, col)


func _text(cx: float, y: float, text: String, size: int, col: Color, outline := true) -> void:
	var pos := Vector2(cx - 360.0, y)
	if outline:
		draw_string_outline(ui_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 720.0, size, maxi(4, int(float(size) / 5.0)), Color(0.02, 0.08, 0.15, 0.9))
	draw_string(ui_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 720.0, size, col)


func _text_left(x: float, y: float, text: String, size: int, col: Color) -> void:
	draw_string(ui_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


func _text_w(text: String, size: int) -> float:
	return ui_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x


func _dashed(a: Vector2, b: Vector2, col: Color, width: float, dash := 14.0) -> void:
	var ln := a.distance_to(b)
	if ln < 1.0:
		return
	var dir := (b - a) / ln
	var d := 0.0
	while d < ln:
		draw_line(a + dir * d, a + dir * minf(d + dash, ln), col, width)
		d += dash * 2.0


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


func _clock(sec: float) -> String:
	var s := maxi(int(ceil(sec)), 0)
	return str(int(s / 60.0)) + ":" + ("%02d" % (s % 60))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	shake_off = shake_vec + Vector2(xoff, 0.0)
	draw_set_transform(shake_off)
	_draw_world()
	_draw_radar_shadows()
	_draw_strikes()
	_draw_bridges()
	_draw_lasers()
	_draw_entities()
	_draw_fx()
	_draw_lock_lines()
	if state != State.DEAD:
		_draw_player()
	_draw_eshots()
	_draw_emissiles()
	_draw_flashes()
	shake_off = Vector2(xoff, 0.0)
	draw_set_transform(shake_off)
	var xl := -xoff
	var xr := VW + xoff
	_draw_vignette()
	if mode == Mode.BATTLE and state == State.PLAY:
		var ba := 0.10 + 0.06 * sin(t * 4.0)
		draw_rect(Rect2(xl, 0.0, 18.0, vh), Color(1, 0.15, 0.1, ba))
		draw_rect(Rect2(xr - 18.0, 0.0, 18.0, vh), Color(1, 0.15, 0.1, ba))
	if over_land and state == State.PLAY:
		var la := 0.18 + 0.14 * sin(t * 18.0)
		draw_rect(Rect2(xl, 0.0, 30.0, vh), Color(1, 0.05, 0.05, la))
		draw_rect(Rect2(xr - 30.0, 0.0, 30.0, vh), Color(1, 0.05, 0.05, la))
	if hurt_t > 0.0:
		var ha := hurt_t / 0.25 * 0.45
		draw_rect(Rect2(xl, 0.0, xr - xl, 30.0), Color(1, 0.1, 0.1, ha))
		draw_rect(Rect2(xl, vh - 30.0, xr - xl, 30.0), Color(1, 0.1, 0.1, ha))
		draw_rect(Rect2(xl, 0.0, 26.0, vh), Color(1, 0.1, 0.1, ha))
		draw_rect(Rect2(xr - 26.0, 0.0, 26.0, vh), Color(1, 0.1, 0.1, ha))
	_draw_popups()
	if state == State.PLAY or state == State.PAUSED:
		_draw_hud()
		_draw_banner()
	match state:
		State.TITLE:
			_draw_title()
		State.DEAD:
			_draw_dead()
		State.PAUSED:
			_draw_paused()


func _update_chunks() -> void:
	# Terrain is drawn once per chunk of rows into its own canvas item and then
	# only moved, instead of redrawing every block every frame.
	var top_w := dist + anchor_y + ROW * 5.0
	var bot_w := dist - (vh - anchor_y) - ROW * 2.0
	var c_lo := floori(bot_w / (ROW * CHUNK_ROWS))
	var c_hi := floori(top_w / (ROW * CHUNK_ROWS))
	_ensure_rows(maxi((c_hi + 1) * CHUNK_ROWS + 1, 0))
	var added := false
	var xc := int(ceil(xoff / COLW))
	if xc != chunk_cols:
		chunk_cols = xc
		for k in chunks.keys():
			chunks[k].queue_free()
		chunks.clear()
		wrecks.clear()
	for k in chunks.keys():
		if k < c_lo or k > c_hi:
			chunks[k].queue_free()
			chunks.erase(k)
	for ci in range(c_lo, c_hi + 1):
		if not chunks.has(ci):
			var n := Node2D.new()
			n.show_behind_parent = true
			n.draw.connect(_draw_chunk.bind(n, ci))
			add_child(n)
			chunks[ci] = n
			added = true
		var node: Node2D = chunks[ci]
		node.position = shake_vec + Vector2(xoff, _sy(float(ci * CHUNK_ROWS) * ROW))
	if added:
		# far chunks first, so nearer blocks overlap them
		var keys: Array = chunks.keys()
		keys.sort()
		keys.reverse()
		for i in keys.size():
			move_child(chunks[keys[i]], i)
	var low := dist - (vh - anchor_y) - 200.0
	wrecks = wrecks.filter(func(wk): return wk[1] > low)


func _draw_chunk(n: Node2D, ci: int) -> void:
	cv = n
	var r0 := ci * CHUNK_ROWS
	var r1 := r0 + CHUNK_ROWS - 1
	# pass 1: water (plus the red kill zones of fortified rows)
	for r in range(r0, r1 + 1):
		var y := -float(r + 1 - r0) * ROW
		var rr := maxi(r, 0)
		var B: Dictionary = BIOMES[rows_b[rr]]
		var cc: float = rows_cc[rr]
		var fort: bool = rows_m[rr] == Mode.FORT and cc >= 0.0
		for col in COLS:
			if not _cell_is_water(rr, col):
				continue
			var x := col * COLW
			var wc: Color = B["water"] if (col + r) % 2 == 0 else B["water2"]
			n.draw_rect(Rect2(x, y, COLW, ROW + 1.0), wc)
			var hsh := _hash(col, r)
			if not _cell_is_water(rr + 1, col):
				n.draw_rect(Rect2(x, y, COLW, LV + 10.0), B["shade"])
			elif B["prop"] == "pine" and hsh < 60:
				_cube(Rect2(x + 6.0, y + 12.0, 22.0, 12.0), 4.0, Color("#f4f8fc"), Color("#b9cde0"), false)
			elif hsh < 110:
				n.draw_rect(Rect2(x + 4.0 + float(hsh % 18), y + 18.0, 14.0, 4.0), Color(0.75, 0.9, 1.0, 0.75))
			if fort:
				var a0 := x
				var a1 := x + COLW
				var tint := Color(1.0, 0.12, 0.18, 0.26 if (col + r) % 2 == 0 else 0.34)
				var lend := minf(a1, cc - CORR_HW)
				if lend > a0:
					n.draw_rect(Rect2(a0, y, lend - a0, ROW + 1.0), tint)
				var rstart := maxf(a0, cc + CORR_HW)
				if rstart < a1:
					n.draw_rect(Rect2(rstart, y, a1 - rstart, ROW + 1.0), tint)
	# pass 2: land blocks, far rows first so nearer blocks overlap them
	for r in range(r1, r0 - 1, -1):
		var y := -float(r + 1 - r0) * ROW
		var rr := maxi(r, 0)
		var B: Dictionary = BIOMES[rows_b[rr]]
		var battle: bool = rows_m[rr] == Mode.BATTLE
		var prop: String = B["prop"]
		for col in range(-chunk_cols, COLS + chunk_cols):
			if _cell_is_water(rr, col):
				continue
			var x := col * COLW
			var near_water := _cell_is_water(rr, col - 1) or _cell_is_water(rr, col + 1) \
				or _cell_is_water(rr + 1, col) or _cell_is_water(maxi(rr - 1, 0), col)
			var hsh := _hash(col, r)
			if near_water:
				var bank: Color = B["bank"]
				_cube(Rect2(x, y - LV, COLW, ROW), LV, bank, bank.darkened(0.3))
				continue
			var top_col: Color = B["land2"] if hsh % 5 == 0 else B["land"]
			if prop == "city" and hsh % 7 == 1:
				top_col = Color("#5b6270")
			_cube(Rect2(x, y - LV, COLW, ROW), LV, top_col, top_col.darkened(0.35))
			if battle and hsh < 130:
				_ellipse(Vector2(x + 20.0, y - LV + 20.0), 17.0, 11.0, Color(0.12, 0.09, 0.08, 0.55))
				_ellipse(Vector2(x + 20.0, y - LV + 21.0), 9.0, 6.0, Color(0.05, 0.04, 0.04, 0.6))
				continue
			if battle and hsh > 935:
				_cube(Rect2(x + 8.0, y - 2.0 * LV + 10.0, 24.0, 18.0), 8.0, Color("#3a3a3a"), Color("#1f1f1f"), false)
				wrecks.append([x, float((r + 1) * ROW), hsh])
				continue
			_draw_prop(prop, B, x, y, hsh)
	cv = self


func _draw_world() -> void:
	# animated bits on top of the cached terrain: corridor beacons and fires
	var top_w := dist + anchor_y + ROW * 3.0
	var bot_w := dist - (vh - anchor_y) - ROW
	var r_lo := maxi(int(floor(bot_w / ROW)), 0)
	var r_hi := int(floor(top_w / ROW))
	_ensure_rows(r_hi + 1)
	for r in range(r_lo, r_hi + 1):
		var cc: float = rows_cc[r]
		if rows_m[r] != Mode.FORT or cc < 0.0:
			continue
		var y := _sy((r + 1) * ROW)
		var lit := (r + int(t * 10.0)) % 5 == 0
		for side in [-1.0, 1.0]:
			var bx: float = cc + side * CORR_HW
			if lit:
				draw_circle(Vector2(bx, y + 20.0), 16.0, Color(0.3, 1.0, 0.5, 0.35))
			_cube(Rect2(bx - 6.0, y + 12.0, 12.0, 12.0), 5.0, Color("#b7ffcf") if lit else C_SAFE, Color("#15803d"), false)
	for wk in wrecks:
		var y := _sy(wk[1])
		if y < -120.0 or y > vh + 60.0:
			continue
		_draw_wreck_fx(wk[0], y, wk[2])


func _draw_prop(prop: String, B: Dictionary, x: float, y: float, hsh: int) -> void:
	var tree: Color = B["tree"]
	var tree_side: Color = B["tree_side"]
	var rock: Color = B["rock"]
	match prop:
		"tree":
			if hsh < 200:
				var lvls := 2.0 + float(hsh % 2)
				_cube(Rect2(x + 4.0, y - lvls * LV + 2.0, COLW - 8.0, COLW - 8.0), (lvls - 1.0) * LV, tree, tree_side)
				cv.draw_rect(Rect2(x + 10.0, y - lvls * LV + 7.0, 9.0, 6.0), tree.lightened(0.3))
			elif hsh > 955:
				_cube(Rect2(x + 3.0, y - 2.0 * LV + 1.0, COLW - 6.0, COLW - 6.0), LV, rock, rock.darkened(0.35))
		"pine":
			if hsh < 220:
				_cube(Rect2(x + 5.0, y - 2.0 * LV + 4.0, 30.0, 30.0), LV, tree, tree_side)
				cv.draw_rect(Rect2(x + 5.0, y - 2.0 * LV + 4.0, 30.0, 8.0), Color("#f4f8fc"))
				_cube(Rect2(x + 10.0, y - 3.0 * LV + 4.0, 20.0, 20.0), LV, tree, tree_side)
				cv.draw_rect(Rect2(x + 10.0, y - 3.0 * LV + 4.0, 20.0, 7.0), Color("#f4f8fc"))
				_cube(Rect2(x + 15.0, y - 4.0 * LV + 4.0, 10.0, 10.0), LV * 0.6, Color("#f4f8fc"), tree_side)
			elif hsh > 950:
				_cube(Rect2(x + 3.0, y - 2.0 * LV + 1.0, COLW - 6.0, COLW - 6.0), LV, rock, rock.darkened(0.35))
		"cactus":
			if hsh < 90:
				_cube(Rect2(x + 15.0, y - 4.0 * LV, 10.0, 10.0), 2.6 * LV, tree, tree_side, false)
				_cube(Rect2(x + 25.0, y - 3.0 * LV, 8.0, 8.0), 0.9 * LV, tree, tree_side, false)
				_cube(Rect2(x + 7.0, y - 3.4 * LV, 8.0, 8.0), 1.0 * LV, tree, tree_side, false)
			elif hsh > 910:
				_cube(Rect2(x + 2.0, y - 3.0 * LV + 2.0, 36.0, 36.0), 2.0 * LV, rock, rock.darkened(0.35))
				cv.draw_rect(Rect2(x + 2.0, y - 3.0 * LV + 2.0, 36.0, 6.0), rock.lightened(0.2))
		"jungle":
			if hsh < 440:
				var lvls := 2.0 + float(hsh % 3)
				_cube(Rect2(x + 1.0, y - lvls * LV + 2.0, COLW - 2.0, COLW - 4.0), (lvls - 1.0) * LV, tree, tree_side)
				cv.draw_rect(Rect2(x + 8.0, y - lvls * LV + 8.0, 12.0, 8.0), tree.lightened(0.25))
				cv.draw_rect(Rect2(x + 22.0, y - lvls * LV + 20.0, 8.0, 6.0), tree.lightened(0.15))
		"city":
			if hsh < 430:
				var lvls := 2.0 + float(hsh % 4)
				var tops := [Color("#c7ccd6"), Color("#9fb3c8"), Color("#d9c7a7")]
				var top: Color = tops[hsh % 3]
				var trc := Rect2(x + 3.0, y - lvls * LV + 2.0, COLW - 6.0, COLW - 6.0)
				var depth := (lvls - 1.0) * LV
				_cube(trc, depth, top, top.darkened(0.45))
				cv.draw_rect(Rect2(trc.position.x + 6.0, trc.position.y + 6.0, 10.0, 10.0), top.darkened(0.15))
				var wy := trc.end.y + 4.0
				while wy < trc.end.y + depth - 6.0:
					for wx in [trc.position.x + 5.0, trc.position.x + 15.0, trc.position.x + 25.0]:
						var lit := (_hash(int(wx), int(wy)) % 3) == 0
						cv.draw_rect(Rect2(wx, wy, 5.0, 5.0), Color("#ffe08a") if lit else Color("#3b4250"))
					wy += 10.0
		"lava":
			if hsh < 130:
				var glow := 0.6 + 0.3 * sin(t * 3.0 + float(hsh))
				cv.draw_rect(Rect2(x + 4.0, y - LV + 14.0, 30.0, 5.0), Color(1.0, 0.45 * glow + 0.2, 0.08))
				cv.draw_rect(Rect2(x + 18.0, y - LV + 6.0, 5.0, 26.0), Color(1.0, 0.4 * glow + 0.2, 0.08))
			elif hsh > 900:
				_cube(Rect2(x + 4.0, y - 3.0 * LV + 4.0, 32.0, 32.0), 2.0 * LV, rock, rock.darkened(0.4))
				cv.draw_rect(Rect2(x + 14.0, y - 3.0 * LV + 10.0, 10.0, 6.0), Color("#ff7a1a"))


func _draw_wreck_fx(x: float, y: float, hsh: int) -> void:
	for i in 3:
		var fh := 8.0 + randf() * 10.0
		draw_rect(Rect2(x + 10.0 + i * 7.0, y - 2.0 * LV + 10.0 - fh, 6.0, fh), Color("#ff9d2e") if i % 2 == 0 else Color("#ffd166"))
	for i in 3:
		var k := fmod(t * 30.0 + float(i) * 26.0 + float(hsh), 80.0)
		draw_circle(Vector2(x + 20.0 + sin(k * 0.08) * 6.0, y - 2.0 * LV - k), 8.0 + k * 0.12, Color(0.25, 0.25, 0.27, 0.45 * (1.0 - k / 80.0)))


func _draw_radar_shadows() -> void:
	# terrain masking: the area behind a rock spire (seen from a SAM) is safe from its radar
	for e in enemies:
		if e["kind"] != "sam" or e["dead"] or not e["active"] or e["cool"] > 0.0:
			continue
		var sy := _sy(e["w"])
		if sy < -40.0 or sy > vh:
			continue
		var from := Vector2(e["x"], sy - 12.0)
		for c in covers:
			var r := _ent_rect(c)
			if r.end.y < -100.0 or r.position.y > vh + 100.0:
				continue
			r = Rect2(r.position.x - 4.0, r.position.y - 44.0, r.size.x + 8.0, r.size.y + 48.0)
			var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			var mid := r.get_center() - from
			var lo := INF
			var hi := -INF
			var c_lo := Vector2.ZERO
			var c_hi := Vector2.ZERO
			for cn in corners:
				var p: Vector2 = cn
				var a := mid.angle_to(p - from)
				if a < lo:
					lo = a
					c_lo = p
				if a > hi:
					hi = a
					c_hi = p
			var far_lo := c_lo + (c_lo - from).normalized() * 1400.0
			var far_hi := c_hi + (c_hi - from).normalized() * 1400.0
			draw_colored_polygon(PackedVector2Array([c_lo, c_hi, far_hi, far_lo]), Color(0.45, 0.95, 1.0, 0.2))
			draw_line(c_lo, far_lo, Color(0.5, 1.0, 1.0, 0.45), 2.0)
			draw_line(c_hi, far_hi, Color(0.5, 1.0, 1.0, 0.45), 2.0)


func _draw_lock_lines() -> void:
	if state != State.PLAY:
		return
	var to := Vector2(px, plane_y)
	var lt := maxf(LOCK_TIME - 0.1 * float(stage), 1.0)
	for e in enemies:
		if e["kind"] != "sam" or e["dead"] or not e["active"] or e["cool"] > 0.0:
			continue
		var sy := _sy(e["w"])
		if sy < -40.0 or sy > vh - 40.0:
			continue
		var from := Vector2(e["x"], sy - 12.0)
		if e["masked"]:
			_dashed(from, from.lerp(to, 0.3), Color(0.7, 0.75, 0.8, 0.5), 2.0, 8.0)
		else:
			var k: float = clampf(e["lock"] / lt, 0.0, 1.0)
			_dashed(from, to, Color(1.0, 0.2, 0.2, 0.3 + 0.6 * k), 2.0 + 3.0 * k, 10.0)


func _draw_strikes() -> void:
	for s in strikes:
		var c := Vector2(s["x"], _sy(s["w"]))
		if c.y < -100.0 or c.y > vh + 100.0:
			continue
		var k: float = 1.0 - s["t"] / s["max"]
		var pulse := 0.5 + 0.5 * sin(t * 18.0)
		_ellipse(c, 80.0, 52.0, Color(1.0, 0.15, 0.1, 0.10 + 0.25 * k))
		draw_arc(c, 80.0 * (1.0 - k) + 8.0, 0.0, TAU, 40, Color(1.0, 0.3, 0.2, 0.6 + 0.4 * pulse), 4.0)
		draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color(1, 0.3, 0.2, 0.9), 3.0)
		draw_line(c + Vector2(0, -18), c + Vector2(0, 18), Color(1, 0.3, 0.2, 0.9), 3.0)


func _draw_bridges() -> void:
	for b in bridges:
		if not b["alive"]:
			continue
		var sy := _sy(b["w"])
		if sy < -80.0 or sy > vh + 80.0:
			continue
		var deck := Color("#c9a27a")
		if b["hit"] > 0.0:
			deck = Color("#fff3d6")
		var bl := -xoff - 40.0
		var bwd := VW + 2.0 * xoff + 80.0
		draw_rect(Rect2(bl, sy - 22.0, bwd, 40.0), deck)
		draw_rect(Rect2(bl, sy + 18.0, bwd, 22.0), Color("#7d5a3a"))
		var x := floorf(bl / 40.0) * 40.0
		while x < bl + bwd:
			draw_rect(Rect2(x, sy - 22.0, 3.0, 40.0), Color("#a77d55"))
			draw_rect(Rect2(x + 2.0, sy + 18.0, 2.0, 22.0), Color("#5e4129"))
			x += 40.0
		draw_rect(Rect2(bl, sy - 22.0, bwd, 6.0), Color("#e3c39d"))
		draw_rect(Rect2(bl, sy + 6.0, bwd, 4.0), Color("#b48a63"))
		if b["hp"] < b["maxhp"]:
			var fr := float(b["hp"]) / float(b["maxhp"])
			_rrect(Rect2(VW * 0.5 - 110.0, sy - 62.0, 220.0, 22.0), Color(0.03, 0.09, 0.16, 0.8), 11.0)
			_rrect(Rect2(VW * 0.5 - 106.0, sy - 58.0, 212.0 * fr, 14.0), Color("#ff9d2e"), 7.0)


func _draw_lasers() -> void:
	for L in lasers:
		var sy := _sy(L["w"])
		if sy < -40.0 or sy > vh + 40.0:
			continue
		var a := 0.75 + 0.25 * sin(t * 22.0 + float(L["w"]) * 0.01)
		for s in L["segs"]:
			var seg: Vector2 = s
			var wdt := seg.y - seg.x
			draw_rect(Rect2(seg.x, sy - 9.0, wdt, 18.0), Color(1.0, 0.1, 0.2, 0.22 * a))
			draw_rect(Rect2(seg.x, sy - 3.0, wdt, 6.0), Color(1.0, 0.25, 0.3, a))
			draw_rect(Rect2(seg.x, sy - 1.0, wdt, 2.0), Color(1.0, 0.92, 0.92, a))
			for ex in [seg.x, seg.y]:
				_cube(Rect2(ex - 8.0, sy - 22.0, 16.0, 14.0), 16.0, Color("#9aa3ae"), Color("#4b5563"), false)
				draw_rect(Rect2(ex - 3.0, sy - 18.0, 6.0, 6.0), Color("#ff4d5e"))


func _draw_entities() -> void:
	for d in depots:
		var r := _ent_rect(d)
		if r.end.y < -60.0 or r.position.y > vh + 60.0:
			continue
		_ellipse(Vector2(r.get_center().x + 8.0, r.end.y + 6.0), 48.0, 10.0, Color(0.02, 0.15, 0.3, 0.32))
		var fl: bool = d["flash"] > 0.0
		var top_r := Rect2(r.position.x, r.position.y, r.size.x, 52.0)
		var front_r := Rect2(r.position.x, r.position.y + 52.0, r.size.x, r.size.y - 52.0)
		draw_rect(front_r, Color.WHITE if fl else Color("#c8102e"))
		for i in 3:
			draw_rect(Rect2(front_r.position.x, front_r.position.y + 6.0 + i * 14.0, front_r.size.x, 6.0), Color.WHITE)
		draw_rect(top_r, Color.WHITE if fl else Color("#ff4d5e"))
		draw_rect(top_r.grow(-1.0), Color("#c8102e"), false, 2.0)
		_ptext("FUEL", Vector2(top_r.get_center().x, top_r.position.y + 15.0), 3.0, Color.WHITE, 1)

	for k in kits:
		var r := _ent_rect(k)
		if r.end.y < -60.0 or r.position.y > vh + 60.0:
			continue
		var bob := sin(t * 4.0 + float(k["w"]) * 0.01) * 4.0
		_ellipse(Vector2(r.get_center().x + 6.0, r.end.y + 4.0), 30.0, 8.0, Color(0.02, 0.15, 0.3, 0.3))
		var amt: int = k["amt"]
		var top := Color("#4ade80") if amt < 20 else Color("#facc15")
		var side := Color("#15803d") if amt < 20 else Color("#a16207")
		var box := Rect2(r.position.x, r.position.y + bob, r.size.x, 44.0)
		_cube(box, 16.0, top, side, false)
		draw_rect(box, side, false, 2.0)
		var c := box.get_center()
		draw_rect(Rect2(c.x - 5.0, c.y - 15.0, 10.0, 30.0), Color.WHITE)
		draw_rect(Rect2(c.x - 15.0, c.y - 5.0, 30.0, 10.0), Color.WHITE)
		_ptext("+" + str(amt) + "%", Vector2(c.x, box.position.y - 26.0), 3.0, top, 1, C_INK)

	for c in wcrates:
		var r := _ent_rect(c)
		if r.end.y < -60.0 or r.position.y > vh + 60.0:
			continue
		var cid: String = c["id"]
		var col: Color = SPECIALS[cid]["col"]
		var bob := sin(t * 3.5 + float(c["w"]) * 0.01) * 5.0
		var ctr := r.get_center() + Vector2(0, bob)
		_ellipse(Vector2(r.get_center().x + 6.0, r.end.y + 4.0), 34.0, 9.0, Color(0.02, 0.15, 0.3, 0.3))
		draw_circle(ctr, 44.0 + 4.0 * sin(t * 6.0), Color(col.r, col.g, col.b, 0.22))
		var cano := ctr + Vector2(0, -74.0)
		draw_line(cano + Vector2(-34, 6), ctr + Vector2(-24, -30), Color(1, 1, 1, 0.7), 2.0)
		draw_line(cano + Vector2(34, 6), ctr + Vector2(24, -30), Color(1, 1, 1, 0.7), 2.0)
		var dome := PackedVector2Array()
		for k in 13:
			var ang := PI + PI * float(k) / 12.0
			dome.append(cano + Vector2(cos(ang) * 40.0, sin(ang) * 26.0 + 6.0))
		draw_colored_polygon(dome, Color("#f4f8fc"))
		draw_rect(Rect2(cano.x - 6.0, cano.y - 20.0, 12.0, 26.0), col)
		var box := Rect2(ctr.x - 28.0, ctr.y - 30.0, 56.0, 46.0)
		_cube(box, 14.0, col, col.darkened(0.45), false)
		draw_rect(box, C_OUTLINE, false, 3.0)
		draw_rect(Rect2(box.position.x + 4.0, box.position.y + 4.0, 48.0, 6.0), col.lightened(0.35))
		_ptext(String(SPECIALS[cid]["icon"]), Vector2(ctr.x, box.position.y + 9.0), 4.0, Color.WHITE, 1, C_INK)
		_ptext(String(SPECIALS[cid]["name"]), Vector2(ctr.x, cano.y - 46.0), 2.5, col, 1, C_INK)

	for e in enemies:
		if e["dead"]:
			continue
		var r := _ent_rect(e)
		if r.end.y < -60.0 or r.position.y > vh + 60.0:
			continue
		_draw_enemy(e, r)

	for cv in covers:
		var r := _ent_rect(cv)
		if r.end.y < -120.0 or r.position.y > vh + 60.0:
			continue
		var B: Dictionary = BIOMES[_biome_at(cv["w"])]
		var rock: Color = B["rock"]
		if B["prop"] == "lava" or B["prop"] == "jungle":
			rock = Color("#7b7f86")
		_ellipse(Vector2(r.get_center().x, r.end.y + 2.0), 44.0, 12.0, Color(0.9, 0.97, 1.0, 0.45))
		var h := 3.0 * LV
		_cube(Rect2(r.position.x, r.position.y - h + 8.0, r.size.x, r.size.y - 8.0), h, rock.lightened(0.15), rock.darkened(0.35))
		draw_rect(Rect2(r.position.x + 8.0, r.position.y - h + 14.0, 20.0, 12.0), rock.lightened(0.3))
		draw_rect(Rect2(r.position.x, r.position.y - h + 8.0, r.size.x, r.size.y - 8.0), rock.darkened(0.5), false, 2.0)


func _draw_enemy(e: Dictionary, r: Rect2) -> void:
	var fl: bool = e["flash"] > 0.0
	var flip: bool = e["vx"] < 0.0
	var c := r.get_center()
	var kind: String = e["kind"]
	var B: Dictionary = BIOMES[_biome_at(e["w"])]
	var camo: Color = B["camo"]
	var camo2: Color = B["camo2"]
	var aim := (Vector2(px, plane_y) - c).normalized()
	match kind:
		"boat":
			_ellipse(c + Vector2(0, 22), 50.0, 8.0, Color(0.9, 0.97, 1.0, 0.5))
			var wake_x := c.x + 50.0 if flip else c.x - 64.0
			draw_rect(Rect2(wake_x, c.y - 8.0, 14.0, 6.0), Color(0.9, 0.97, 1.0, 0.7))
			_vsprite(BOAT, c, 8.0, {"X": Color("#ff7a45"), "G": Color("#ffe0c2")}, 6.0, flip, true, fl)
		"heli":
			_ellipse(c + Vector2(14, 36), 30.0, 8.0, Color(0.02, 0.15, 0.3, 0.32))
			_vsprite(HELI, c, 8.0, {"X": Color("#e5484d"), "C": Color("#9fd6ff")}, 5.0, not flip, true, fl)
			var hub := c + Vector2(-4.0 if flip else 4.0, -20.0)
			var a := t * 26.0
			var arm := Vector2(cos(a), sin(a) * 0.3) * 46.0
			draw_line(hub - arm, hub + arm, Color("#2b2f36"), 5.0)
			_ellipse(hub, 46.0, 13.0, Color(1, 1, 1, 0.16))
		"ship":
			_ellipse(c + Vector2(0, 28), 66.0, 10.0, Color(0.9, 0.97, 1.0, 0.5))
			_vsprite(SHIP, c, 8.0, {"X": Color("#8b95a5"), "G": Color("#e9edf2"), "T": Color("#e5484d")}, 7.0, flip, true, fl)
		"jet":
			_ellipse(c + Vector2(18, 40), 34.0, 8.0, Color(0.02, 0.15, 0.3, 0.3))
			_vsprite(JET, c, 8.0, {"X": Color("#b8c0cc"), "R": Color("#e5484d")}, 4.0, flip, true, fl)
			var tail_x := c.x + 44.0 if flip else c.x - 52.0
			draw_rect(Rect2(tail_x, c.y - 4.0, 10.0, 8.0), Color("#ffb347"))
		"tank":
			_vsprite(TANK, c, 7.0, {"T": camo, "C": camo2, "B": Color("#2b2f36")}, 4.0, false, true, fl)
		"truck":
			_vsprite(TRUCK, c, 8.0, {"G": camo, "C": camo2, "K": Color("#1f2329")}, 4.0, false, true, fl)
		"aa":
			_cube(Rect2(c.x - 22.0, c.y - 10.0, 44.0, 28.0), 8.0, Color.WHITE if fl else camo, camo.darkened(0.4))
			draw_circle(c + Vector2(0, 2), 12.0, Color.WHITE if fl else camo2)
			var perp := Vector2(-aim.y, aim.x)
			for s in [-5.0, 5.0]:
				draw_line(c + Vector2(0, 2) + perp * s, c + Vector2(0, 2) + perp * s + aim * 30.0, Color("#2b2f36"), 4.0)
			draw_circle(c + Vector2(0, 2), 5.0, Color("#2b2f36"))
		"soldiers":
			var offs := [Vector2(-22, -8), Vector2(0, -12), Vector2(22, -8), Vector2(-11, 8), Vector2(11, 8)]
			for i in offs.size():
				var o: Vector2 = offs[i]
				var bob := sin(t * 8.0 + float(i)) * 1.5
				var p := c + o + Vector2(0, bob)
				draw_rect(Rect2(p.x - 4.0, p.y - 2.0, 8.0, 10.0), C_OUTLINE)
				draw_rect(Rect2(p.x - 3.0, p.y - 1.0, 6.0, 8.0), Color.WHITE if fl else camo)
				draw_rect(Rect2(p.x - 3.0, p.y - 8.0, 6.0, 6.0), Color("#e0b48a"))
				draw_rect(Rect2(p.x - 3.0, p.y - 9.0, 6.0, 3.0), camo2.darkened(0.2))
				if e["fire_t"] < 0.12:
					draw_circle(p + aim * 10.0, 3.0, Color("#ffe08a"))
		"sam":
			_cube(Rect2(c.x - 24.0, c.y - 4.0, 48.0, 30.0), 8.0, Color.WHITE if fl else camo, camo.darkened(0.4))
			for i in 4:
				var mx := c.x - 18.0 + i * 12.0
				draw_rect(Rect2(mx - 1.0, c.y - 31.0, 10.0, 30.0), C_OUTLINE)
				draw_rect(Rect2(mx, c.y - 30.0, 8.0, 28.0), Color("#e9edf2"))
				draw_rect(Rect2(mx, c.y - 30.0, 8.0, 7.0), Color("#e5484d"))
			var dish := c + Vector2(0, 14)
			var da := t * 4.0
			draw_circle(dish, 7.0, camo2)
			draw_line(dish, dish + Vector2(cos(da), sin(da) * 0.5) * 12.0, Color("#2b2f36"), 3.0)
			var lt := maxf(LOCK_TIME - 0.1 * float(stage), 1.0)
			var k: float = clampf(e["lock"] / lt, 0.0, 1.0)
			if k > 0.0 and e["cool"] <= 0.0:
				draw_arc(c, 34.0, 0.0, TAU, 32, Color(1.0, 0.2, 0.2, 0.4 + 0.5 * k), 2.0 + 3.0 * k)
		"battery":
			_ellipse(c + Vector2(0, 34), 40.0, 9.0, Color(0.9, 0.97, 1.0, 0.45))
			_cube(Rect2(c.x - 30.0, c.y - 24.0, 60.0, 46.0), 14.0, Color("#b7bec9"), Color("#6b7280"))
			draw_rect(Rect2(c.x - 30.0, c.y - 24.0, 60.0, 46.0), Color("#ffcc00"), false, 3.0)
			var perp := Vector2(-aim.y, aim.x)
			var tc := c + Vector2(0, -2)
			for s in [-6.0, 6.0]:
				draw_line(tc + perp * s, tc + perp * s + aim * 34.0, Color("#2b2f36"), 5.0)
			draw_circle(tc, 15.0, Color.WHITE if fl else Color("#b91c1c"))
			draw_circle(tc, 6.0, Color("#2b2f36"))
			if out_corridor and int(t * 8.0) % 2 == 0:
				draw_circle(tc + aim * 38.0, 7.0, Color("#ffe08a"))
	var maxhp: int = e["maxhp"]
	if maxhp > 1 and e["hp"] < maxhp:
		var bw := maxf(r.size.x, 48.0)
		_rrect(Rect2(c.x - bw * 0.5, r.position.y - 16.0, bw, 10.0), Color(0, 0, 0, 0.5), 5.0)
		_rrect(Rect2(c.x - bw * 0.5 + 1.0, r.position.y - 15.0, (bw - 2.0) * float(e["hp"]) / float(maxhp), 8.0), Color("#ff9d2e"), 4.0)


func _draw_fx() -> void:
	for s in smoke:
		var k: float = s["life"] / s["max"]
		draw_circle(Vector2(s["x"], _sy(s["w"])), s["r"], Color(0.85, 0.85, 0.88, 0.5 * k))
	for b in bullets:
		var sy := _sy(b["w"])
		var col := C_DRONE if b["drone"] else Color("#fff2a8")
		_rrect(Rect2(b["x"] - 4.0, sy - 14.0, 8.0, 28.0), Color(col.r, col.g, col.b, 0.25), 4.0)
		_rrect(Rect2(b["x"] - 2.5, sy - 11.0, 5.0, 22.0), col, 2.5)
	for r in rockets:
		var rsy := _sy(r["w"])
		draw_rect(Rect2(r["x"] - 6.0, rsy - 16.0, 12.0, 28.0), C_OUTLINE)
		draw_rect(Rect2(r["x"] - 4.0, rsy - 14.0, 8.0, 24.0), Color("#f97316"))
		draw_rect(Rect2(r["x"] - 4.0, rsy - 14.0, 8.0, 6.0), Color("#fff2a8"))
		draw_circle(Vector2(r["x"], rsy + 14.0), 6.0 + randf() * 3.0, Color("#ffd166"))
	for m in missiles:
		var sy := _sy(m["w"])
		draw_rect(Rect2(m["x"] - 5.0, sy - 12.0, 10.0, 22.0), Color("#eef2f6"))
		draw_rect(Rect2(m["x"] - 5.0, sy - 12.0, 10.0, 6.0), Color("#ff5a5f"))
		draw_rect(Rect2(m["x"] - 4.0, sy + 10.0, 8.0, 8.0 + randf() * 8.0), Color("#ff9d2e"))
	for p in debris:
		var sy := _sy(p["w"])
		var s: float = p["s"] * clampf(p["life"] / p["max"] + 0.35, 0.0, 1.0)
		var col: Color = p["col"]
		draw_set_transform(shake_off + Vector2(p["x"], sy), p["rot"])
		draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), col)
		draw_rect(Rect2(-s * 0.5, s * 0.5, s, s * 0.45), col.darkened(0.45))
	draw_set_transform(shake_off)
	for c in coin_fx:
		var sy := _sy(c["w"])
		_cube(Rect2(c["x"] - 8.0, sy - 8.0, 16.0, 16.0), 6.0, C_GOLD, Color("#c99400"), false)
		draw_rect(Rect2(c["x"] - 4.0, sy - 4.0, 5.0, 5.0), Color("#fff2a8"))
	for f in flare_fx:
		var p := Vector2(f["x"], f["sy"])
		var k: float = clampf(f["life"] / 1.4, 0.0, 1.0)
		draw_circle(p, 14.0, Color(1.0, 0.8, 0.4, 0.3 * k))
		draw_circle(p, 6.0, Color(1.0, 0.95, 0.8, k))


func _draw_eshots() -> void:
	for s in eshots:
		var p := Vector2(s["x"], s["sy"])
		match s["kind"]:
			"shell":
				draw_circle(p, 16.0, Color(1.0, 0.45, 0.1, 0.35))
				draw_circle(p, 11.0, Color("#2b2f36"))
				draw_circle(p, 6.0, Color("#ff9d2e"))
			"flak":
				draw_circle(p, 10.0, Color(1.0, 0.85, 0.2, 0.35))
				draw_circle(p, 5.0, Color("#ffd166"))
				draw_circle(p, 2.5, Color.WHITE)
			_:
				draw_circle(p, 9.0, Color(1.0, 0.3, 0.25, 0.35))
				draw_circle(p, 5.0, C_RED)
				draw_circle(p, 2.5, Color.WHITE)


func _draw_emissiles() -> void:
	for m in emissiles:
		var p := Vector2(m["x"], m["sy"])
		var dir := Vector2(m["vx"], m["vy"]).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var tail := p - dir * 26.0
		if m.get("lethal", false):
			tail = p - dir * 34.0
			draw_line(tail, p, C_OUTLINE, 13.0)
			draw_line(tail, p, Color("#2b2f36"), 9.0)
			draw_line(p - dir * 9.0, p, C_RED, 9.0)
			draw_circle(tail - dir * 8.0, 9.0 + randf() * 4.0, Color("#ffd166"))
			if not m["lost"]:
				draw_arc(p, 20.0, 0.0, TAU, 20, Color(1, 0.15, 0.15, 0.9), 3.0)
			continue
		draw_line(tail, p, C_OUTLINE, 10.0)
		draw_line(tail, p, Color("#e9edf2"), 6.0)
		draw_line(p - dir * 6.0, p, Color("#e5484d"), 6.0)
		draw_line(tail - perp * 7.0, tail + perp * 7.0, Color("#9aa3ae"), 3.0)
		draw_circle(tail - dir * 6.0, 6.0 + randf() * 3.0, Color("#ffb347"))
		if m["decoy"] == null and int(t * 12.0) % 2 == 0:
			draw_arc(p, 16.0, 0.0, TAU, 20, Color(1, 0.2, 0.2, 0.8), 2.0)


func _draw_flashes() -> void:
	for f in flashes:
		var k: float = f["life"] / f["max"]
		var c := Vector2(f["x"], _sy(f["w"]))
		var r: float = f["r"] * (1.15 - 0.3 * k)
		draw_circle(c, r, Color(1.0, 0.35, 0.12, 0.35 * k))
		draw_circle(c, r * 0.75, Color(1.0, 0.55, 0.1, 0.6 * k))
		draw_circle(c, r * 0.5, Color(1.0, 0.88, 0.4, 0.85 * k))
		draw_circle(c, r * 0.25, Color(1, 1, 1, k))
		draw_arc(c, r * 1.12, 0.0, TAU, 48, Color(1.0, 0.95, 0.77, 0.6 * k), 4.0)


func _draw_player() -> void:
	var pc := Vector2(px, plane_y)
	var sid: String = _active().get("id", "") if state == State.PLAY else ""
	if laser_on and state == State.PLAY:
		var lh := plane_y - 30.0 - laser_top
		var wob := 2.0 * sin(t * 50.0)
		draw_rect(Rect2(px - 14.0 - wob, laser_top, 28.0 + 2.0 * wob, lh), Color(1.0, 0.3, 0.85, 0.3))
		draw_rect(Rect2(px - 6.0, laser_top, 12.0, lh), Color("#ff4dd2"))
		draw_rect(Rect2(px - 2.0, laser_top, 4.0, lh), Color.WHITE)
		draw_circle(Vector2(px, laser_top), 14.0 + randf() * 6.0, Color(1.0, 0.6, 0.95, 0.8))
	if rail_fx > 0.0:
		var ra := rail_fx / 0.15
		draw_rect(Rect2(rail_x - 18.0 * ra, -40.0, 36.0 * ra, plane_y), Color(1.0, 0.85, 0.2, 0.4 * ra))
		draw_rect(Rect2(rail_x - 5.0, -40.0, 10.0, plane_y), Color(1.0, 0.95, 0.6, ra))
	if emp_fx > 0.0:
		var ek := 1.0 - emp_fx / 0.5
		draw_arc(pc, 40.0 + 380.0 * ek, 0.0, TAU, 64, Color(0.4, 0.7, 1.0, 1.0 - ek), 10.0)
		draw_circle(pc, 40.0 + 380.0 * ek, Color(0.4, 0.7, 1.0, 0.15 * (1.0 - ek)))
	var blink := invuln > 0.0 and int(t * 14.0) % 2 == 0
	if not blink:
		var body: Dictionary = F22_COLS
		if hurt_t > 0.15:
			body = {"N": Color.WHITE, "X": Color.WHITE, "L": Color.WHITE, "C": Color.WHITE, "T": Color.WHITE, "O": Color.WHITE}
		_ellipse(pc + Vector2(26, 60), 30.0, 9.0, Color(0.02, 0.1, 0.2, 0.35))
		if state == State.PLAY:
			var flick := 10.0 + randf() * 12.0
			draw_rect(Rect2(px - 11.0, plane_y + 30.0, 6.0, flick), Color(1.0, 0.7, 0.28, 0.9))
			draw_rect(Rect2(px + 5.0, plane_y + 30.0, 6.0, flick), Color(1.0, 0.7, 0.28, 0.9))
			draw_rect(Rect2(px - 10.0, plane_y + 30.0, 4.0, flick * 0.5), Color(0.6, 0.9, 1.0, 0.9))
			draw_rect(Rect2(px + 6.0, plane_y + 30.0, 4.0, flick * 0.5), Color(0.6, 0.9, 1.0, 0.9))
			if firing:
				draw_circle(Vector2(px, plane_y - 36.0), 7.0 * (0.6 + randf() * 0.4), Color(1.0, 0.95, 0.6, 0.85))
		_vsprite(F22, pc, 4.5, body, 3.0)
	if sid == "wingmen":
		var dcols := {"N": C_DRONE.darkened(0.3), "X": C_DRONE, "L": C_DRONE.lightened(0.2), "C": Color("#3a7bd5"), "T": C_DRONE.darkened(0.2), "O": Color("#ff9d2e")}
		for side in [-1.0, 1.0]:
			_vsprite(F22, pc + Vector2(80.0 * side, 26.0), 3.0, dcols, 2.0)
	elif sid == "drones":
		for i in 3:
			var dp := _drone_pos(i)
			draw_circle(dp, 13.0, C_OUTLINE)
			draw_circle(dp, 10.0, Color("#a3e635"))
			draw_circle(dp, 4.0, Color.WHITE)
	if shield_hp > 0.0:
		var sa := 0.35 + 0.25 * sin(t * 5.0) + shield_fx
		draw_circle(pc, 48.0, Color(0.4, 0.95, 1.0, 0.10 + shield_fx * 0.4))
		draw_arc(pc, 48.0, 0.0, TAU, 48, Color(0.5, 0.95, 1.0, clampf(sa, 0.0, 1.0)), 4.0)
	# over-land warning: ring fills up until the ground missile launches
	if state == State.PLAY and land_t > 0.0:
		var k := clampf(land_t / _land_limit(), 0.0, 1.0)
		var fast := int(t * (6.0 + 14.0 * k)) % 2 == 0
		draw_arc(pc, 56.0, 0.0, TAU, 48, Color(1, 0.2, 0.2, 0.25), 6.0)
		draw_arc(pc, 56.0, -PI * 0.5, -PI * 0.5 + TAU * k, 48, C_RED if fast else Color("#ffb4b8"), 6.0)
		if over_land:
			var left := maxf(_land_limit() - land_t, 0.0)
			var msg := "BACK TO RIVER " + ("%.1f" % left) if not land_fired else "MISSILE INCOMING!"
			_ptext(msg, pc + Vector2(0, -96.0), 3.0, C_RED if fast else Color.WHITE, 1, C_INK)
	# missile lock warning
	if state == State.PLAY:
		if lock_level > 0.1:
			var s := 64.0 - 26.0 * clampf(lock_level, 0.0, 1.0)
			var col := Color(1.0, 0.2, 0.2, 0.5 + 0.5 * lock_level)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var cn := pc + Vector2(sx * s, sy * s)
					draw_line(cn, cn - Vector2(sx * 16.0, 0), col, 4.0)
					draw_line(cn, cn - Vector2(0, sy * 16.0), col, 4.0)
			if lock_level > 0.55 and int(t * 8.0) % 2 == 0:
				_ptext("LOCK", pc + Vector2(0, -s - 30.0), 3.0, C_RED, 1, C_INK)
		elif masked:
			_ptext("MASKED", pc + Vector2(0, -78.0), 2.5, C_CYAN, 1, C_INK)


func _draw_vignette() -> void:
	for i in 10:
		var k := 1.0 - float(i) / 10.0
		draw_rect(Rect2(-xoff, float(i) * 22.0, VW + 2.0 * xoff, 22.0), Color(0.02, 0.07, 0.12, 0.5 * k * k))
		draw_rect(Rect2(-xoff, vh - float(i + 1) * 20.0, VW + 2.0 * xoff, 20.0), Color(0.02, 0.07, 0.12, 0.5 * k * k))


func _draw_popups() -> void:
	for p in popups:
		var a := clampf(p["life"] / 0.4, 0.0, 1.0)
		var pxs: float = p["px"]
		var text: String = p["text"]
		if p["badge"]:
			var w := _ptext_width(text, pxs) + 40.0
			var h := 7.0 * pxs + 28.0
			var c := Vector2(p["x"], p["sy"])
			draw_set_transform(Vector2(xoff, 0.0) + c, deg_to_rad(-3.0))
			_rrect(Rect2(-w * 0.5, -h * 0.5 + 6.0, w, h), Color(0.72, 0.53, 0.04, a), 14.0)
			_rrect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(1.0, 0.82, 0.25, a), 14.0)
			_ptext(text, Vector2(0.0, -3.5 * pxs), pxs, Color(C_INK.r, C_INK.g, C_INK.b, a), 1)
			draw_set_transform(Vector2(xoff, 0.0))
		else:
			var col: Color = p["col"]
			col.a = a
			_ptext(text, Vector2(p["x"], p["sy"]), pxs, col, 1, Color(0.04, 0.14, 0.25, a))


func _draw_banner() -> void:
	if not banner.is_empty():
		var life: float = banner["life"]
		var a := clampf(life / 0.5, 0.0, 1.0) * clampf((3.2 - life) / 0.25, 0.0, 1.0)
		var col: Color = banner["col"]
		var y := vh * 0.33
		var title: String = banner["title"]
		var pxs := 6.0
		while pxs > 3.0 and _ptext_width(title, pxs) > VW - 80.0:
			pxs -= 0.5
		_rrect(Rect2(24.0, y - 20.0, VW - 48.0, 7.0 * pxs + 90.0), Color(0.02, 0.06, 0.12, 0.82 * a), 22.0, Color(col.r, col.g, col.b, a), 4)
		_ptext(title, Vector2(VW * 0.5, y), pxs, Color(col.r, col.g, col.b, a), 1, Color(0, 0, 0, 0.6 * a))
		var sub: String = banner["sub"]
		draw_string(ui_font, Vector2(24.0, y + 7.0 * pxs + 46.0), sub, HORIZONTAL_ALIGNMENT_CENTER, VW - 48.0, 25, Color(1, 1, 1, a))
	if not toasts.is_empty():
		var tt: Dictionary = toasts[0]
		var life: float = tt["life"]
		var a := clampf(life / 0.3, 0.0, 1.0) * clampf((2.4 - life) / 0.2, 0.0, 1.0)
		var text: String = tt["text"]
		var pxs := 3.5
		while pxs > 2.0 and _ptext_width(text, pxs) > VW - 120.0:
			pxs -= 0.5
		var w := _ptext_width(text, pxs) + 48.0
		var y := vh * 0.22 - 20.0 * (1.0 - a)
		_rrect(Rect2(VW * 0.5 - w * 0.5, y, w, 7.0 * pxs + 28.0), Color(1.0, 0.82, 0.25, 0.95 * a), 16.0)
		_ptext(text, Vector2(VW * 0.5, y + 14.0), pxs, Color(C_INK.r, C_INK.g, C_INK.b, a), 1)


func _draw_hud() -> void:
	# Otto badge, score, level bar
	var badge := Rect2(24.0, 44.0, 96.0, 96.0)
	_rrect(badge, C_PANEL, 26.0, C_GOLD, 4)
	_vsprite(OTTER, badge.get_center(), 6.0, OTTER_COLS, 0.0, false, false)
	_text_left(138.0, 66.0, "SCORE", 20, Color("#cfe8ff"))
	_ptext(_fmt(int(score)), Vector2(138.0, 78.0), 5.5, Color.WHITE, 0, Color(0.02, 0.07, 0.12, 0.6))
	var sbar := Rect2(138.0, 126.0, 230.0, 14.0)
	_rrect(sbar, Color(1, 1, 1, 0.16), 7.0)
	_rrect(Rect2(sbar.position, Vector2(maxf(sbar.size.x * clampf(supply / supply_need, 0.0, 1.0), 10.0), sbar.size.y)), Color("#f97316"), 7.0)
	_ptext("SUPPLY", Vector2(378.0, 125.0), 2.5, Color("#ffb347"))
	if supply_ready and not picking:
		var sr := _supply_rect()
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		_rrect(sr, Color(0.97, 0.45, 0.09, 0.75 + 0.25 * pulse), 16.0, Color(1, 1, 1, 0.6 + 0.4 * pulse), 3)
		_ptext("SUPPLY READY", Vector2(sr.position.x + 16.0, sr.position.y + 9.0), 3.0, Color.WHITE, 0, C_INK)
		var hint_sup := "tap to choose" if not tv_mode else "hold OK to choose"
		_text_left(sr.position.x + 16.0, sr.position.y + 47.0, hint_sup, 15, Color.WHITE)
	if unlocked < UNLOCKS.size():
		var nxt: String = SPECIALS[UNLOCKS[unlocked][0]]["name"]
		_text_left(24.0, 172.0, "Next weapon: " + nxt.capitalize() + " at " + _fmt(int(UNLOCKS[unlocked][1])), 15, Color("#cfe8ff"))

	# coins + pause
	var pr := _pause_rect()
	var ctext := _fmt(coins)
	var cw := _ptext_width(ctext, 4.0) + 82.0
	var cr := Rect2(pr.position.x - 14.0 - cw, 54.0, cw, 64.0)
	_rrect(cr, C_PANEL, 32.0)
	_cube(Rect2(cr.position.x + 18.0, cr.position.y + 16.0, 26.0, 26.0), 7.0, C_GOLD, Color("#c99400"), false)
	draw_rect(Rect2(cr.position.x + 24.0, cr.position.y + 22.0, 8.0, 8.0), Color("#fff2a8"))
	_ptext(ctext, Vector2(cr.position.x + 58.0, cr.position.y + 18.0), 4.0, Color.WHITE)
	_rrect(pr, C_PANEL, 22.0)
	draw_rect(Rect2(pr.position.x + 28.0, pr.position.y + 26.0, 10.0, 32.0), Color.WHITE)
	draw_rect(Rect2(pr.position.x + 46.0, pr.position.y + 26.0, 10.0, 32.0), Color.WHITE)

	var cy := 116.0
	# stage + countdown
	var B: Dictionary = BIOMES[_biome_at(_pw())]
	var stage_txt := "STAGE " + str(stage + 1) + " | " + String(B["name"])
	var timer_txt := "BATTLE IN " + _clock(STAGE_TIME - stage_clock)
	var timer_col := C_CYAN
	if mode == Mode.BATTLE:
		timer_txt = "BATTLEFIELD! SURVIVE " + _clock(battle_t)
		timer_col = C_RED if int(t * 3.0) % 2 == 0 else Color("#ffb4b8")
	var ky := cy + 42.0
	for line in [[stage_txt, Color.WHITE], [timer_txt, timer_col]]:
		var txt: String = line[0]
		var kw := _ptext_width(txt, 2.5) + 24.0
		_rrect(Rect2(VW - 24.0 - kw, ky, kw, 32.0), C_PANEL, 10.0)
		_ptext(txt, Vector2(VW - 24.0 - kw * 0.5, ky + 8.0), 2.5, line[1], 1)
		ky += 38.0

	# fuel, life (+ shield), flares, special weapon slots
	var gy := _panel_y()
	_rrect(Rect2(30.0, gy, VW - 60.0, 266.0), Color(0.03, 0.094, 0.157, 0.88), 28.0)
	var bx := 178.0
	var bw := VW - 178.0 - 140.0
	_ptext("FUEL", Vector2(54.0, gy + 18.0), 3.5, Color.WHITE)
	var frac := fuel / max_fuel
	var seg_w := bw / 10.0
	for i in 10:
		var col := Color(1, 1, 1, 0.14)
		if float(i) < frac * 10.0:
			if frac <= 0.25:
				col = C_RED
			elif i < 2:
				col = Color("#ff9d2e")
			else:
				col = C_GOLD
		_rrect(Rect2(bx + i * seg_w, gy + 14.0, seg_w - 6.0, 26.0), col, 6.0)
	_ptext(str(int(round(frac * 100.0))) + "%", Vector2(VW - 54.0, gy + 18.0), 3.5, Color.WHITE, 2)
	var hfrac := health / 100.0
	var hcol := C_SAFE
	if hfrac <= 0.25:
		hcol = C_RED
	elif hfrac <= 0.5:
		hcol = Color("#facc15")
	_ptext("LIFE", Vector2(54.0, gy + 56.0), 3.5, Color.WHITE)
	_rrect(Rect2(bx, gy + 52.0, bw - 6.0, 26.0), Color(1, 1, 1, 0.14), 8.0)
	if hfrac > 0.0:
		_rrect(Rect2(bx, gy + 52.0, maxf((bw - 6.0) * hfrac, 12.0), 26.0), hcol, 8.0)
	if shield_hp > 0.0:
		_rrect(Rect2(bx, gy + 80.0, maxf((bw - 6.0) * shield_hp / 100.0, 8.0), 7.0), C_CYAN, 3.0)
	_ptext(str(int(ceil(health))) + "%", Vector2(VW - 54.0, gy + 56.0), 3.5, hcol if hfrac <= 0.5 else Color.WHITE, 2)
	_ptext("FLARE", Vector2(54.0, gy + 100.0), 3.5, Color.WHITE)
	var fmax: int = FLARES_MAX
	for i in fmax:
		var fc := Vector2(bx + 18.0 + i * 46.0, gy + 110.0)
		var pts := PackedVector2Array([fc + Vector2(0, -13), fc + Vector2(13, 0), fc + Vector2(0, 13), fc + Vector2(-13, 0)])
		if i < flares:
			draw_colored_polygon(pts, C_CYAN)
		else:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.14))
			if i == flares:
				var rk := flare_rc / FLARE_RECHARGE
				draw_rect(Rect2(fc.x - 13.0, fc.y + 16.0, 26.0 * rk, 4.0), C_CYAN)
	if shield_hp > 0.0:
		_text_left(bx + 18.0 + fmax * 46.0, gy + 118.0, "SHIELD " + str(int(ceil(shield_hp))) + "%", 19, C_CYAN)
	else:
		_text_left(bx + 18.0 + fmax * 46.0, gy + 118.0, "auto vs missiles", 18, Color("#9fc4e0"))
	for i in _slot_count():
		var r := _slot_rect(i)
		if i >= slots.size():
			_rrect(r, Color(1, 1, 1, 0.04), 14.0, Color(1, 1, 1, 0.18), 2)
			draw_string(ui_font, Vector2(r.position.x, r.position.y + 44.0), "EMPTY SLOT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1, 0.35))
			continue
		var sl: Dictionary = slots[i]
		var sdef: Dictionary = SPECIALS[sl["id"]]
		var scol: Color = sdef["col"]
		var chosen := i == sel
		_rrect(r, Color(scol.r, scol.g, scol.b, 0.18 if chosen else 0.07), 14.0, C_GOLD if chosen else Color(1, 1, 1, 0.22), 4 if chosen else 1)
		var ib := Rect2(r.position.x + 10.0, r.position.y + 13.0, 46.0, 46.0)
		_rrect(ib, scol, 10.0)
		_ptext(String(sdef["icon"]), Vector2(ib.get_center().x, ib.position.y + 9.0), 4.0, Color.WHITE, 1, C_INK)
		var tx := ib.end.x + 10.0
		var tw := r.end.x - tx - 10.0
		var nm: String = sdef["name"]
		var fs := 18
		while fs > 12 and _text_w(nm, fs) > tw:
			fs -= 1
		_text_left(tx, r.position.y + 30.0, nm, fs, Color.WHITE if chosen else Color("#cfe8ff"))
		var e: float = clampf(sl["energy"] / 100.0, 0.0, 1.0)
		_rrect(Rect2(tx, r.position.y + 42.0, tw, 14.0), Color(1, 1, 1, 0.15), 7.0)
		_rrect(Rect2(tx, r.position.y + 42.0, maxf(tw * e, 8.0), 14.0), scol if e > 0.2 else C_RED, 7.0)
		if sl["war"]:
			_ptext("WAR", Vector2(r.end.x - 8.0, r.position.y + 6.0), 2.0, C_GOLD, 2)
	if picking:
		var top := _panel_y() - 186.0
		_rrect(Rect2(24.0, top, VW - 48.0, 172.0), Color(0.03, 0.094, 0.157, 0.94), 22.0, Color(0.97, 0.45, 0.09, 1.0), 3)
		_ptext("CHOOSE YOUR SUPPLY DROP", Vector2(VW * 0.5, top + 14.0), 3.0, Color("#ffb347"), 1)
		_rrect(Rect2(60.0, top + 42.0, (VW - 120.0) * clampf(pick_t / 6.0, 0.0, 1.0), 6.0), Color("#ffb347"), 3.0)
		for i in unlocked:
			var r := _pick_rect(i)
			var pid: String = UNLOCKS[i][0]
			var pd: Dictionary = SPECIALS[pid]
			var pc: Color = pd["col"]
			var foc := i == pick_focus and (tv_mode or not DisplayServer.is_touchscreen_available())
			_rrect(r, Color(pc.r, pc.g, pc.b, 0.22), 12.0, C_GOLD if foc else Color(1, 1, 1, 0.3), 4 if foc else 1)
			var ib := Rect2(r.get_center().x - 22.0, r.position.y + 8.0, 44.0, 44.0)
			_rrect(ib, pc, 10.0)
			_ptext(String(pd["icon"]), Vector2(ib.get_center().x, ib.position.y + 8.0), 4.0, Color.WHITE, 1, C_INK)
			var short: String = String(pd["name"]).split(" ")[0]
			var fs := 15
			while fs > 10 and _text_w(short, fs) > r.size.x - 6.0:
				fs -= 1
			draw_string(ui_font, Vector2(r.position.x, r.position.y + 78.0), short, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color.WHITE)
	# hint
	var hint := "Drag to fly. Hold to fire, lift to glide over FUEL."
	if tv_mode:
		hint = "D-pad fly | OK fire on/off | hold OK switch | Back pause"
	if not slots.is_empty() and not tv_mode:
		hint = "Tap a weapon to switch. Hold to fire it."
	if fire_latch:
		hint = "AUTO FIRE ON - press OK to stop (glide over FUEL)"
	var hint_col := Color("#cfe8ff")
	var blink := int(t * 4.0) % 2 == 0
	if over_land:
		hint = "OVER LAND! Ground missiles lock on in a moment"
		hint_col = C_RED if blink else Color("#ffb4b8")
	elif out_corridor:
		hint = "DANGER ZONE! Get back in the green corridor"
		hint_col = C_RED if blink else Color("#ffb4b8")
	elif lock_level > 0.3:
		hint = "MISSILE LOCK! Put a rock between you and the SAM"
		hint_col = C_RED if blink else Color("#ffb4b8")
	elif frac < 0.2 and blink:
		hint = "LOW FUEL! Find a fuel tank"
		hint_col = C_RED
	elif hfrac < 0.25 and blink:
		hint = "LOW LIFE! Grab a repair kit"
		hint_col = C_RED
	elif mode == Mode.BATTLE:
		hint = "Rocks block radar. Shoot SAM launchers first."
		hint_col = Color("#ffd9d9")
	draw_string(ui_font, Vector2(30.0, gy + 248.0), hint, HORIZONTAL_ALIGNMENT_CENTER, VW - 60.0, 20, hint_col)


func _dim(a := 0.7) -> void:
	draw_rect(Rect2(-xoff, 0.0, VW + 2.0 * xoff, vh), Color(0.02, 0.07, 0.12, a))


func _draw_title() -> void:
	_dim(0.55)
	var y := vh * 0.12
	_vsprite(OTTER, Vector2(VW * 0.5, y), 10.0, OTTER_COLS, 5.0)
	_ptext("RIVERWING", Vector2(VW * 0.5, y + 90.0), 12.0, C_GOLD, 1, Color("#8a5a00"))
	_ptext("PROTOTYPE V0.6", Vector2(VW * 0.5, y + 194.0), 3.0, Color("#cfe8ff"), 1)
	var lines := [
		"Drag to fly your jet anywhere on screen.",
		"Hold to fire. Lift to glide over FUEL.",
	]
	if tv_mode:
		lines = [
			"D-pad: fly. OK: auto fire on / off.",
			"Hold OK: switch weapon or pick supply.",
		]
	elif not DisplayServer.is_touchscreen_available():
		lines = [
			"Mouse drag or arrows/WASD to fly.",
			"Hold Space or the mouse to fire. Q: switch.",
		]
	lines.append_array([
		"Kills fill SUPPLY: a weapon crate drops in.",
		"Fortified zones: stay in the green corridor.",
		"Every 5 min: a battlefield. Survive 45 s.",
		"Hide behind rocks to break missile locks.",
		"Flares fire automatically at missiles.",
		"Over land: 2 s, then a missile hits.",
	])
	_rrect(Rect2(36.0, y + 244.0, VW - 72.0, 416.0), C_PANEL, 24.0)
	for i in lines.size():
		_text(VW * 0.5, y + 292.0 + i * 48.0, lines[i], 24, Color.WHITE, false)
	if int(t * 2.0) % 2 == 0:
		_ptext("PRESS OK TO FLY" if tv_mode else "TAP TO FLY", Vector2(VW * 0.5, y + 698.0), 8.0, C_GOLD, 1, Color("#8a5a00"))
	if best > 0:
		_ptext("BEST " + _fmt(best), Vector2(VW * 0.5, y + 778.0), 4.0, C_CYAN, 1, C_INK)


func _draw_dead() -> void:
	_dim(0.65)
	var y := vh * 0.24
	var head := "CRASHED!"
	if death_reason == "OUT OF FUEL":
		head = "OUT OF FUEL"
	elif death_reason == "YOUR JET WAS SHOT DOWN" or death_reason == "SHOT DOWN OVER LAND":
		head = "SHOT DOWN!"
	_ptext(head, Vector2(VW * 0.5, y), 10.0, C_RED, 1, Color("#5c0b0e"))
	if death_reason != "OUT OF FUEL":
		_text(VW * 0.5, y + 112.0, death_reason, 26, Color("#ffd9d9"))
	_rrect(Rect2(90.0, y + 150.0, VW - 180.0, 270.0), C_PANEL, 26.0)
	_text_left(130.0, y + 196.0, "SCORE", 22, Color("#cfe8ff"))
	_ptext(_fmt(int(score)), Vector2(130.0, y + 212.0), 7.0, Color.WHITE)
	_text_left(130.0, y + 306.0, "BEST  " + _fmt(best), 24, C_CYAN)
	_text_left(130.0, y + 346.0, "Stage " + str(stage + 1) + "   |   Weapons " + str(weapons_got) + "   |   Kills " + str(kills), 22, Color("#d6e6f5"))
	_text_left(130.0, y + 384.0, "Bridges " + str(bridges_down) + "   |   Coins " + str(coins), 22, Color("#d6e6f5"))
	if dead_t > 0.7 and int(t * 2.0) % 2 == 0:
		_ptext("TAP TO FLY AGAIN", Vector2(VW * 0.5, y + 470.0), 6.0, C_GOLD, 1, Color("#8a5a00"))


func _draw_paused() -> void:
	_dim(0.72)
	_ptext("PAUSED", Vector2(VW * 0.5, vh * 0.2), 9.0, Color.WHITE, 1, C_INK)
	var items := _menu_items()
	for i in items.size():
		var r := _menu_rect(i)
		var id: String = items[i][0]
		var foc := i == menu_focus
		var col := Color(1, 1, 1, 0.08)
		if id.begins_with("battle") or id in ["fort", "scenery", "supply", "god"]:
			col = Color(0.97, 0.45, 0.09, 0.14)
		if id == "resume":
			col = Color(0.29, 0.87, 0.5, 0.25)
		_rrect(r, col, 16.0, C_GOLD if foc else Color(1, 1, 1, 0.25), 4 if foc else 1)
		draw_string(ui_font, Vector2(r.position.x, r.position.y + 42.0), String(items[i][1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, Color.WHITE)
