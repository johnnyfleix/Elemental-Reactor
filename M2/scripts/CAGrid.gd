# CAGrid.gd
# The heart of M2: a 100×100 Cellular Automaton grid with:
#   - Double-buffer update pattern (read from _front, write to _back, then swap)
#   - Per-element propagation rules (fire spread, water flow, smoke rise)
#   - Spatial index bridge: RigidBody2D positions → CA cell writes
#   - Signal emission for the renderer and M1 element system
#
# PERFORMANCE DESIGN:
#   - All rules run in a single O(COLS*ROWS) pass per tick.
#   - No per-cell Node or signal — pure data array iteration.
#   - Update runs on a Timer (not _process) at a fixed CA tick rate,
#     decoupled from the render framerate.
#   - The "updated" flag prevents a cell being processed twice per tick
#     when fluid movement cascades.
#
# Attach to: Node2D named "CAGrid" inside M2/scenes/M2Main.tscn
class_name CAGrid
extends Node2D

# ── Grid dimensions ───────────────────────────────────────────────────────────
const COLS        : int   = 100
const ROWS        : int   = 100
const TICK_RATE   : float = 1.0 / 60.0  # Target: 60 CA ticks/sec

# ── Cell size in world pixels ─────────────────────────────────────────────────
# With a 1280×720 viewport the grid occupies the full play area.
# CELL_W = 1280/100 = 12.8,  CELL_H = 720/100 = 7.2
var cell_w : float
var cell_h : float

# ── Double-buffer ─────────────────────────────────────────────────────────────
# _front = current state (read-only during tick)
# _back  = next state (written during tick)
# After the tick, front and back are swapped by reference — zero copying.
var _front : Array  # Array[CACell], size COLS*ROWS
var _back  : Array  # Array[CACell], size COLS*ROWS

# ── Spatial index: maps RigidBody2D → grid cell ───────────────────────────────
# Populated each tick by _sync_rigidbodies().
# This lets M1 RigidBody2D objects "stamp" themselves into the CA grid,
# creating a bridge between the two simulation layers.
var _rb_registry : Array  # Array[RigidBody2D] — registered M1 bodies

# ── Tick accumulator ──────────────────────────────────────────────────────────
var _tick_accum    : float = 0.0
var _tick_count    : int   = 0   # total ticks since scene load (for debug)

# ── Performance measurement ───────────────────────────────────────────────────
var _last_tick_us  : int   = 0   # microseconds for last tick (for benchmark UI)

# ── Signals ───────────────────────────────────────────────────────────────────
## Emitted after every CA tick. CARenderer connects to this.
signal grid_updated(front_buffer: Array)

## Emitted when fire at a grid cell has burned out (for M3 MaterialEventBus).
signal cell_burned_out(grid_pos: Vector2i)

## Emitted when water extinguishes fire at a cell.
signal cell_extinguished(grid_pos: Vector2i)


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	var vp := get_viewport_rect().size
	cell_w = vp.x / float(COLS)
	cell_h = vp.y / float(ROWS)

	_init_buffers()
	_rb_registry = []


func _init_buffers() -> void:
	_front = []
	_back  = []
	_front.resize(COLS * ROWS)
	_back.resize(COLS * ROWS)
	for i in range(COLS * ROWS):
		_front[i] = CACell.new()
		_back[i]  = CACell.new()


# ── Main update ───────────────────────────────────────────────────────────────
# We use _process (not _physics_process) so the CA tick rate is decoupled
# from Godot's physics step. This prevents the physics engine and CA
# from competing for the same frame budget.
func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum >= TICK_RATE:
		_tick_accum -= TICK_RATE
		_run_tick()


func _run_tick() -> void:
	var t_start := Time.get_ticks_usec()

	# Step 1: Sync RigidBody2D positions into the grid.
	_sync_rigidbodies()

	# Step 2: Clear the updated flag on the back buffer.
	_clear_back()

	# Step 3: Iterate all cells bottom-to-top (important for gravity-driven
	# fluids — processing bottom rows first prevents double-movement).
	for row in range(ROWS - 1, -1, -1):
		for col in range(COLS):
			_process_cell(col, row)

	# Step 4: Swap buffers. _front becomes the new authoritative state.
	var temp := _front
	_front = _back
	_back = temp

	_tick_count += 1
	_last_tick_us = Time.get_ticks_usec() - t_start

	# Emit so CARenderer redraws.
	grid_updated.emit(_front)


# ── Buffer helpers ────────────────────────────────────────────────────────────
func _clear_back() -> void:
	# Copy front → back as the starting state, then clear update flags.
	# This means cells that have no rule applied stay unchanged.
	for i in range(COLS * ROWS):
		_back[i].copy_from(_front[i])
		_back[i].updated = false

func _idx(col: int, row: int) -> int:
	return row * COLS + col

func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS


# ── Spatial index: RigidBody2D → grid ────────────────────────────────────────
## Call this from M2Main to register an M1 element with the CA grid.
func register_body(body: RigidBody2D) -> void:
	if not body in _rb_registry:
		_rb_registry.append(body)


## Remove a body when it queue_free()s (connect to tree_exited signal).
func unregister_body(body: RigidBody2D) -> void:
	_rb_registry.erase(body)


func _sync_rigidbodies() -> void:
	# Write each registered RigidBody2D's element type into the cell
	# it currently occupies. This is the M1→M2 bridge.
	# We don't write into _back directly — we write into _front so the
	# rule pass in this same tick can immediately react to the body.
	for body in _rb_registry:
		if not is_instance_valid(body):
			continue
		var gp := world_to_grid(body.global_position)
		if not _in_bounds(gp.x, gp.y):
			continue
		var cell : CACell = _front[_idx(gp.x, gp.y)]
		# Determine type from class_name — same pattern as M1.
		if body is HeatSource:
			cell.type = CellState.Type.FIRE
		elif body is Flammable:
			cell.type = CellState.Type.WOOD
		elif body is Extinguisher:
			cell.type = CellState.Type.WATER
		elif body is Conductor:
			cell.type = CellState.Type.METAL


# ── Cell rule dispatch ────────────────────────────────────────────────────────
func _process_cell(col: int, row: int) -> void:
	var cell : CACell = _front[_idx(col, row)]

	# Skip cells already moved this tick (prevents double-processing fluids).
	if _back[_idx(col, row)].updated:
		return

	match cell.type:
		CellState.Type.FIRE:
			_rule_fire(col, row, cell)
		CellState.Type.WATER:
			_rule_water(col, row, cell)
		CellState.Type.SMOKE:
			_rule_smoke(col, row, cell)
		CellState.Type.STEAM:
			_rule_steam(col, row, cell)
		CellState.Type.WOOD:
			_rule_wood(col, row, cell)
		# METAL and EMPTY: no movement rules — they stay put.


# ── FIRE rules ────────────────────────────────────────────────────────────────
# Fire rises slightly (gravity_scale = 0 in M1 terms).
# It spreads to adjacent WOOD cells by incrementing their heat.
# After FIRE_LIFETIME ticks it dies and leaves SMOKE.
const FIRE_LIFETIME    : int = 45   # ~0.75s at 60 ticks/sec
const FIRE_SPREAD_PROB : float = 0.55  # Probability to spread sideways each tick

func _rule_fire(col: int, row: int, cell: CACell) -> void:
	var bc : CACell = _back[_idx(col, row)]
	bc.lifetime += 1

	# Age out: fire burns up and produces smoke above it.
	if bc.lifetime >= FIRE_LIFETIME:
		bc.type     = CellState.Type.EMPTY
		bc.lifetime = 0
		bc.updated  = true
		# Produce smoke one cell above if empty.
		if _in_bounds(col, row - 1):
			var above : CACell = _back[_idx(col, row - 1)]
			if above.type == CellState.Type.EMPTY and not above.updated:
				above.type    = CellState.Type.SMOKE
				above.lifetime = 0
				above.updated  = true
		cell_burned_out.emit(Vector2i(col, row))
		return

	# Rise: try to move fire upward into an empty cell.
	if _in_bounds(col, row - 1):
		var above : CACell = _front[_idx(col, row - 1)]
		if above.type == CellState.Type.EMPTY:
			_move_cell(col, row, col, row - 1)
			return

	# Spread: heat adjacent WOOD cells. Probabilistic for organic feel.
	var neighbours := [
		Vector2i(col - 1, row), Vector2i(col + 1, row),
		Vector2i(col, row + 1), Vector2i(col - 1, row - 1),
		Vector2i(col + 1, row - 1),
	]
	for nb in neighbours:
		if not _in_bounds(nb.x, nb.y):
			continue
		var nb_front : CACell = _front[_idx(nb.x, nb.y)]
		var nb_back  : CACell = _back[_idx(nb.x, nb.y)]
		if nb_front.type == CellState.Type.WOOD:
			nb_back.heat += 1
			# Ignite if heat threshold reached (probabilistic).
			if nb_back.heat >= CellState.IGNITION_TICKS[CellState.Type.WOOD]:
				if randf() < FIRE_SPREAD_PROB:
					nb_back.type    = CellState.Type.FIRE
					nb_back.heat    = 0
					nb_back.updated = true
		elif nb_front.type == CellState.Type.WATER:
			# Fire meets water: extinguish both, produce steam above.
			_back[_idx(col, row)].type    = CellState.Type.EMPTY
			_back[_idx(col, row)].updated = true
			nb_back.type    = CellState.Type.STEAM
			nb_back.updated = true
			cell_extinguished.emit(Vector2i(col, row))
			return


# ── WATER rules ───────────────────────────────────────────────────────────────
# Water falls (gravity) then spreads sideways like a fluid.
# Uses a random left/right bias each tick for natural spread.
const WATER_SPREAD_DIST : int = 3  # How many cells water can spread sideways

func _rule_water(col: int, row: int, cell: CACell) -> void:
	# Try fall straight down.
	if _in_bounds(col, row + 1):
		var below : CACell = _front[_idx(col, row + 1)]
		if below.type == CellState.Type.EMPTY:
			_move_cell(col, row, col, row + 1)
			return
		# Fall diagonally.
		var dir : int = 1 if randf() > 0.5 else -1
		for d in [dir, -dir]:
			if _in_bounds(col + d, row + 1):
				var diag : CACell = _front[_idx(col + d, row + 1)]
				if diag.type == CellState.Type.EMPTY:
					_move_cell(col, row, col + d, row + 1)
					return

	# Spread sideways if can't fall.
	var dir : int = 1 if randf() > 0.5 else -1
	for d in [dir, -dir]:
		var target_col = col + d
		if _in_bounds(target_col, row):
			var side : CACell = _front[_idx(target_col, row)]
			if side.type == CellState.Type.EMPTY:
				_move_cell(col, row, target_col, row)
				return


# ── WOOD rules ────────────────────────────────────────────────────────────────
# Wood doesn't move but accumulates heat from neighbouring fire.
# When ignited it becomes FIRE.
func _rule_wood(col: int, row: int, _cell: CACell) -> void:
	# Heat accumulation is handled by FIRE's spread rule above.
	# Here we just check if the cell's heat has crossed the threshold
	# (in case heat accumulated without being consumed by the fire rule).
	var bc : CACell = _back[_idx(col, row)]
	if bc.heat >= CellState.IGNITION_TICKS[CellState.Type.WOOD]:
		bc.type    = CellState.Type.FIRE
		bc.heat    = 0
		bc.updated = true


# ── SMOKE rules ───────────────────────────────────────────────────────────────
# Smoke rises and dissipates after SMOKE_LIFETIME ticks.
const SMOKE_LIFETIME : int = 90  # ~1.5s

func _rule_smoke(col: int, row: int, cell: CACell) -> void:
	var bc : CACell = _back[_idx(col, row)]
	bc.lifetime += 1
	if bc.lifetime >= SMOKE_LIFETIME:
		bc.type    = CellState.Type.EMPTY
		bc.updated = true
		return
	# Rise.
	if _in_bounds(col, row - 1):
		var above : CACell = _front[_idx(col, row - 1)]
		if above.type == CellState.Type.EMPTY:
			_move_cell(col, row, col, row - 1)
			return
	# Drift sideways randomly if blocked.
	var dir := 1 if randf() > 0.5 else -1
	if _in_bounds(col + dir, row - 1):
		var diag : CACell = _front[_idx(col + dir, row - 1)]
		if diag.type == CellState.Type.EMPTY:
			_move_cell(col, row, col + dir, row - 1)


# ── STEAM rules ───────────────────────────────────────────────────────────────
# Steam rises faster than smoke, dissipates sooner.
const STEAM_LIFETIME : int = 50

func _rule_steam(col: int, row: int, cell: CACell) -> void:
	var bc : CACell = _back[_idx(col, row)]
	bc.lifetime += 1
	if bc.lifetime >= STEAM_LIFETIME:
		bc.type    = CellState.Type.EMPTY
		bc.updated = true
		return
	# Rise quickly — try 2 cells up.
	for step in [1, 2]:
		if _in_bounds(col, row - step):
			var above : CACell = _front[_idx(col, row - step)]
			if above.type == CellState.Type.EMPTY:
				_move_cell(col, row, col, row - step)
				return
	# Drift.
	var dir := 1 if randf() > 0.5 else -1
	if _in_bounds(col + dir, row):
		var side : CACell = _front[_idx(col + dir, row)]
		if side.type == CellState.Type.EMPTY:
			_move_cell(col, row, col + dir, row)


# ── Move helper ───────────────────────────────────────────────────────────────
# Swaps source cell data into destination in _back, clears source in _back.
# Sets updated=true on destination to prevent re-processing this tick.
func _move_cell(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var src : CACell = _front[_idx(from_col, from_row)]
	var dst : CACell = _back[_idx(to_col, to_row)]

	# Write source data to destination.
	dst.copy_from(src)
	dst.updated = true

	# Clear source in back buffer.
	var src_back : CACell = _back[_idx(from_col, from_row)]
	src_back.reset()
	src_back.updated = true


# ── Public API: paint cells (used by M2Spawner) ───────────────────────────────
## Writes a cell type at a world-space position.
## Safe to call from _process (queued for next tick via _front write).
func paint_cell(world_pos: Vector2, type: int) -> void:
	var gp := world_to_grid(world_pos)
	if _in_bounds(gp.x, gp.y):
		var cell : CACell = _front[_idx(gp.x, gp.y)]
		cell.type     = type
		cell.heat     = 0
		cell.lifetime = 0
		cell.updated  = false


## Paint a circular brush of radius `r` cells.
func paint_circle(world_pos: Vector2, type: int, radius: int) -> void:
	var center := world_to_grid(world_pos)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var col := center.x + dx
				var row := center.y + dy
				if _in_bounds(col, row):
					paint_cell(grid_to_world(Vector2i(col, row)), type)


# ── Coordinate conversion ─────────────────────────────────────────────────────
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_w),
		int(world_pos.y / cell_h)
	)


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		(grid_pos.x + 0.5) * cell_w,
		(grid_pos.y + 0.5) * cell_h
	)


# ── Debug ─────────────────────────────────────────────────────────────────────
func get_tick_time_us() -> int:
	return _last_tick_us


func get_tick_count() -> int:
	return _tick_count
