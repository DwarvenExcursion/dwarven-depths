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
const STRATA := [
	{"at": 0,   "name": "SURFACE",    "stone": 0.10, "gem": 0.07,
		"dirt": SOIL,      "dirt_hi": SOIL_L,    "dirt_lo": SOIL_D,
		"rock": SLATE_L,   "rock_hi": SLATE_XL,  "rock_lo": SLATE,
		"deep": Color("120d10")},
	{"at": 60,  "name": "DEEP EARTH", "stone": 0.18, "gem": 0.06,
		"dirt": SOIL_D,    "dirt_hi": SOIL,      "dirt_lo": SOIL_XD,
		"rock": SLATE,     "rock_hi": SLATE_L,   "rock_lo": SLATE_D,
		"deep": Color("0d0f14")},
	{"at": 130, "name": "CRYSTAL",    "stone": 0.26, "gem": 0.05,
		"dirt": VIOLET_D,  "dirt_hi": VIOLET,    "dirt_lo": VIOLET_XD,
		"rock": SLATE_D,   "rock_hi": SLATE,     "rock_lo": SLATE_XD,
		"deep": Color("100c18")},
	{"at": 210, "name": "MAGMA",      "stone": 0.34, "gem": 0.04,
		"dirt": BARK,      "dirt_hi": RUST,      "dirt_lo": BARK_XD,
		"rock": BARK_XD,   "rock_hi": BARK,      "rock_lo": BLOOD_XD,
		"deep": Color("15080c")},
]


static func stratum(row: int) -> Dictionary:
	var s: Dictionary = STRATA[0]
	for e in STRATA:
		if row >= e["at"]:
			s = e
	return s
