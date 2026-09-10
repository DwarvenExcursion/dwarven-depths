class_name Apollo
extends RefCounted

## Apollo 46 by AdamCYounis. Every colour in the game resolves through this
## file so nothing drifts off-palette. Highlight/shadow pairs are always
## neighbours on the same Apollo ramp -- that is what keeps the bevels from
## looking like arbitrary lightening.

# --- Greys (ramp 40-46) ---
const VOID       := Color("090a14")   # open tunnel / background
const INK        := Color("10141f")
const SLATE_XD   := Color("151d28")
const SLATE_D    := Color("202e37")
const SLATE      := Color("394a50")
const SLATE_L    := Color("577277")
const SLATE_XL   := Color("819796")
const MIST       := Color("a8b5b2")   # body text
const BONE       := Color("c7cfcc")   # beard
const WHITE      := Color("ebede9")   # headings

# --- Blues (ramp 1-6) ---
const NAVY       := Color("172038")
const DENIM      := Color("253a5e")
const STEEL      := Color("3c5e8b")   # tunic shade
const AZURE      := Color("4f8fba")   # tunic
const GEM        := Color("73bed3")
const GEM_HI     := Color("a4dddb")

# --- Reds (ramp 25-30) ---
const BLOOD_XD   := Color("241527")
const BLOOD_D    := Color("411d31")
const BLOOD      := Color("752438")
const FLOOD      := Color("a53030")   # water body
const FLOOD_HI   := Color("cf573c")   # water crest
const EMBER      := Color("da863e")

# --- Browns / golds (ramp 19-24) ---
const BARK_XD    := Color("341c27")
const BARK       := Color("602c2c")
const RUST       := Color("884b2b")   # helmet brim
const BRONZE     := Color("be772b")   # helmet
const AMBER      := Color("de9e41")   # lamp glow
const GOLD       := Color("e8c170")   # lamp core

# --- Earths (ramp 13-18) ---
const SOIL_XD    := Color("4d2b32")
const SOIL_D     := Color("7a4841")   # pick handle
const SOIL       := Color("ad7757")
const SOIL_L     := Color("c09473")
const SAND       := Color("d7b594")   # skin
const SAND_L     := Color("e7d5b3")

# --- Purples (ramp 31-36) ---
const VIOLET_XD  := Color("1e1d39")
const VIOLET_D   := Color("402751")
const VIOLET     := Color("7a367b")

# --- Greens (ramp 7-12) ---
const MOSS_D     := Color("25562e")
const MOSS       := Color("468232")
const LIME       := Color("75a743")


## Depth bands. Stone density climbing is the difficulty curve: more stone
## means more forced detours, and a detour costs depth directly.
## The descent, in seventeen tiers from the surface to row 5000.
##
## Three curves run the whole way down and none of them is linear:
##
## - `stone` rises but flattens. Past about 0.5 the shaft stops being diggable
##   and starts being a wall, so the deep tiers creep rather than climb.
## - `gem` falls but never reaches zero. Gems are blast currency, and a tier
##   that pays nothing is a tier where a wall of stone is a dead end.
## - `cave` is the counterweight. Open space rises with depth, so the deepest
##   rock is the hardest to cut *and* the most likely to have already broken
##   somewhere. It is what keeps a 0.56-stone tier passable.
##
## Depths past the last tier clamp to it -- stratum() keeps the last match
## rather than indexing, so there is no bound to run off.
##
## Every colour is an Apollo 46 constant except `deep`, the bedrock tint
## behind the shaft, which is a per-tier near-black. That exception predates
## this table; the four original tiers all carry one.
const STRATA := [
	{"at": 0,    "name": "SURFACE",    "stone": 0.10, "gem": 0.070, "cave": 0.00,
		"dirt": SOIL,      "dirt_hi": SOIL_L,    "dirt_lo": SOIL_D,
		"rock": SLATE_L,   "rock_hi": SLATE_XL,  "rock_lo": SLATE,
		"deep": Color("120d10")},
	{"at": 60,   "name": "DEEP EARTH", "stone": 0.18, "gem": 0.060, "cave": 0.01,
		"dirt": SOIL_D,    "dirt_hi": SOIL,      "dirt_lo": SOIL_XD,
		"rock": SLATE,     "rock_hi": SLATE_L,   "rock_lo": SLATE_D,
		"deep": Color("0d0f14")},
	{"at": 130,  "name": "CRYSTAL",    "stone": 0.26, "gem": 0.050, "cave": 0.02,
		"dirt": VIOLET_D,  "dirt_hi": VIOLET,    "dirt_lo": VIOLET_XD,
		"rock": SLATE_D,   "rock_hi": SLATE,     "rock_lo": SLATE_XD,
		"deep": Color("100c18")},
	{"at": 210,  "name": "MAGMA",      "stone": 0.34, "gem": 0.040, "cave": 0.03,
		"dirt": BARK,      "dirt_hi": RUST,      "dirt_lo": BARK_XD,
		"rock": BARK_XD,   "rock_hi": BARK,      "rock_lo": BLOOD_XD,
		"deep": Color("15080c")},

	# --- past the old floor -------------------------------------------
	{"at": 310,  "name": "OBSIDIAN",   "stone": 0.38, "gem": 0.036, "cave": 0.05,
		"dirt": SLATE_D,   "dirt_hi": SLATE,     "dirt_lo": SLATE_XD,
		"rock": INK,       "rock_hi": SLATE_XD,  "rock_lo": VOID,
		"deep": Color("07080d")},
	{"at": 430,  "name": "CINDERFALL", "stone": 0.41, "gem": 0.033, "cave": 0.06,
		"dirt": BLOOD_D,   "dirt_hi": BLOOD,     "dirt_lo": BLOOD_XD,
		"rock": BARK_XD,   "rock_hi": BARK,      "rock_lo": BLOOD_XD,
		"deep": Color("170a0e")},
	{"at": 580,  "name": "THE VEIN",   "stone": 0.435, "gem": 0.031, "cave": 0.075,
		"dirt": RUST,      "dirt_hi": BRONZE,    "dirt_lo": BARK,
		"rock": BARK_XD,   "rock_hi": BARK,      "rock_lo": BLOOD_XD,
		"deep": Color("1a0e08")},
	{"at": 760,  "name": "DEEPFORGE",  "stone": 0.455, "gem": 0.029, "cave": 0.085,
		"dirt": BARK,      "dirt_hi": RUST,      "dirt_lo": BARK_XD,
		"rock": SLATE_XD,  "rock_hi": SLATE_D,   "rock_lo": INK,
		"deep": Color("120a0a")},
	{"at": 980,  "name": "SALTWORKS",  "stone": 0.47, "gem": 0.027, "cave": 0.095,
		"dirt": SAND,      "dirt_hi": SAND_L,    "dirt_lo": SOIL_L,
		"rock": SLATE_L,   "rock_hi": SLATE_XL,  "rock_lo": SLATE,
		"deep": Color("141013")},
	{"at": 1250, "name": "GLASSFLOW",  "stone": 0.485, "gem": 0.026, "cave": 0.105,
		"dirt": STEEL,     "dirt_hi": AZURE,     "dirt_lo": DENIM,
		"rock": NAVY,      "rock_hi": DENIM,     "rock_lo": INK,
		"deep": Color("080b16")},
	{"at": 1580, "name": "THE CHOKE",  "stone": 0.50, "gem": 0.025, "cave": 0.115,
		"dirt": MOSS_D,    "dirt_hi": MOSS,      "dirt_lo": SOIL_XD,
		"rock": SLATE_D,   "rock_hi": SLATE,     "rock_lo": SLATE_XD,
		"deep": Color("0a1410")},
	{"at": 1980, "name": "NIGHTROCK",  "stone": 0.51, "gem": 0.024, "cave": 0.125,
		"dirt": VIOLET_D,  "dirt_hi": VIOLET,    "dirt_lo": VIOLET_XD,
		"rock": INK,       "rock_hi": SLATE_XD,  "rock_lo": VOID,
		"deep": Color("0c0a16")},
	{"at": 2460, "name": "THE MARROW", "stone": 0.52, "gem": 0.023, "cave": 0.135,
		"dirt": BONE,      "dirt_hi": WHITE,     "dirt_lo": MIST,
		"rock": SLATE,     "rock_hi": SLATE_L,   "rock_lo": SLATE_D,
		"deep": Color("15161a")},
	{"at": 3040, "name": "COLDIRON",   "stone": 0.53, "gem": 0.022, "cave": 0.145,
		"dirt": SLATE,     "dirt_hi": SLATE_L,   "dirt_lo": SLATE_D,
		"rock": SLATE_XD,  "rock_hi": SLATE_D,   "rock_lo": INK,
		"deep": Color("0d1116")},
	{"at": 3740, "name": "THE SUMP",   "stone": 0.54, "gem": 0.021, "cave": 0.155,
		"dirt": MOSS,      "dirt_hi": LIME,      "dirt_lo": MOSS_D,
		"rock": BLOOD_XD,  "rock_hi": BLOOD_D,   "rock_lo": INK,
		"deep": Color("0a1210")},
	{"at": 4580, "name": "EMBERDEEP",  "stone": 0.55, "gem": 0.020, "cave": 0.165,
		"dirt": FLOOD,     "dirt_hi": FLOOD_HI,  "dirt_lo": BLOOD,
		"rock": BLOOD_XD,  "rock_hi": BLOOD_D,   "rock_lo": INK,
		"deep": Color("1a0709")},
	{"at": 5000, "name": "WORLDHEART", "stone": 0.56, "gem": 0.020, "cave": 0.175,
		"dirt": BRONZE,    "dirt_hi": GOLD,      "dirt_lo": RUST,
		"rock": BARK_XD,   "rock_hi": BARK,      "rock_lo": BLOOD_XD,
		"deep": Color("1c1206")},
]


## The tier a row belongs to. Anything below the last entry clamps to it, so
## the mine keeps generating forever without the table having to.
static func stratum(row: int) -> Dictionary:
	var s: Dictionary = STRATA[0]
	for e in STRATA:
		if row >= e["at"]:
			s = e
	return s
