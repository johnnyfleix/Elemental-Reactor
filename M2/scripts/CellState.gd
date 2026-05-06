# CellState.gd
# Central definition for all cell types used by the CA grid.
# Every other M2 script imports these constants via class_name.
# Adding a new element = add one entry here + handle it in CAGrid.gd.
#
# NOTE: These integer values are used as direct array indices in the
# double-buffer — keep them contiguous starting at 0.
class_name CellState

enum Type {
	EMPTY   = 0,
	FIRE    = 1,
	WOOD    = 2,
	WATER   = 3,
	METAL   = 4,
	SMOKE   = 5,   # Produced when Wood burns out
	STEAM   = 6,   # Produced when Water meets Fire
}

# ── Per-type display colours (used by CARenderer) ────────────────────────────
# Indexed by Type enum value for O(1) lookup.
static var COLOURS: Array[Color] = [
	Color(0, 0, 0, 0),               # EMPTY       — transparent
	Color(1.0,  0.38, 0.04, 1.0),    # FIRE        — deep orange
	Color(0.42, 0.26, 0.1,  1.0),    # WOOD        — brown
	Color(0.18, 0.52, 0.95, 0.88),   # WATER       — blue
	Color(0.50, 0.50, 0.55, 1.0),    # METAL       — steel grey
	Color(0.22, 0.22, 0.25, 0.65),   # SMOKE       — dark translucent
	Color(0.78, 0.88, 1.0,  0.55),   # STEAM       — light translucent
]

# ── Per-type flammability: ticks of fire contact before ignition ──────────────
# 0 = never ignites, >0 = ignition threshold tick count
static var IGNITION_TICKS: Array[int] = [
	0,   # EMPTY
	0,   # FIRE  (already burning)
	8,   # WOOD  — ignites after 8 ticks of fire contact
	0,   # WATER
	0,   # METAL
	0,   # SMOKE
	0,   # STEAM
]

# ── Is this type a fluid that falls/flows? ────────────────────────────────────
static var IS_FLUID: Array[bool] = [
	false,  # EMPTY
	true,   # FIRE  — rises
	false,  # WOOD
	true,   # WATER — falls and spreads
	false,  # METAL
	true,   # SMOKE — rises slowly
	true,   # STEAM — rises
]
