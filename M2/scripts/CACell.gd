# CACell.gd
# Lightweight data object representing a single cell in the CA grid.
# This is NOT a Node — it holds no scene tree overhead.
# The grid stores a flat Array[CACell] of COLS * ROWS cells.
#
# Keeping state here (rather than parallel arrays) makes rule logic
# readable: cell.type, cell.heat, cell.updated — all in one place.
class_name CACell

# ── Core state ────────────────────────────────────────────────────────────────
var type      : int  = CellState.Type.EMPTY  # CellState.Type enum value
var heat      : int  = 0    # Accumulated fire-contact ticks (for ignition)
var updated   : bool = false # Double-buffer flag — has this cell been written this tick?
var lifetime  : int  = 0    # Ticks this cell has existed (used by Fire, Smoke, Steam)


func _init(p_type: int = CellState.Type.EMPTY) -> void:
	type = p_type


# ── Convenience ───────────────────────────────────────────────────────────────
func is_empty() -> bool:
	return type == CellState.Type.EMPTY


func reset() -> void:
	type     = CellState.Type.EMPTY
	heat     = 0
	updated  = false
	lifetime = 0


func copy_from(other: CACell) -> void:
	type     = other.type
	heat     = other.heat
	updated  = other.updated
	lifetime = other.lifetime
