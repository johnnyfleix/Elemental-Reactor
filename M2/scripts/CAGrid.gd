# CAGrid.gd
# The heart of M2: a 100×100 Cellular Automaton grid with:
#   - Single-buffer update pattern with PackedByteArray visited mask
#   - Per-element propagation rules (fire spread, water flow, smoke rise)
#   - Spatial index bridge: RigidBody2D positions → CA cell writes
#   - Signal emission for the renderer and M1 element system
#
# PERFORMANCE DESIGN:
#   - SINGLE BUFFER: cells are modified in-place each tick.
#     A PackedByteArray _visited mask (1 byte/cell, fill(0) via C memset)
#     replaces the old double-buffer scheme.  This eliminates _clear_back(),
#     which was copying 10,000 CACell objects every tick (~1.4 ms alone).
#   - INCREMENTAL fire counter: _fire_count is ±1'd inside each rule,
#     removing the separate O(n) fire-count scan after the tick.
#   - EMPTY early-exit + inlined _idx: skips ~70% of cells cheaply.
#   - All hot loops use while instead of range() to avoid Array allocation.
#
# Attach to: Node2D named "CAGrid" inside M2/scenes/M2Main.tscn
class_name CAGrid
extends Node2D

# ── Grid dimensions ───────────────────────────────────────────────────────────
const COLS: int = 100
const ROWS: int = 100
const TICK_RATE: float = 1.0 / 60.0 # Target: 60 CA ticks/sec

# ── Cell size in world pixels ─────────────────────────────────────────────────
var cell_w: float
var cell_h: float

# ── Single buffer ─────────────────────────────────────────────────────────────
# Cells are mutated in-place.  A PackedByteArray visited mask prevents a cell
# from being processed twice in one tick (replaces the double-buffer pattern).
var _grid: Array # Array[CACell], size COLS*ROWS
var _visited: PackedByteArray # 0 = unvisited this tick, 1 = already processed

# ── Spatial index: maps RigidBody2D → grid cell ───────────────────────────────
var _rb_registry: Array # Array[RigidBody2D]

# ── Tick accumulator ──────────────────────────────────────────────────────────
var _tick_accum: float = 0.0
var _tick_count: int = 0

# ── Performance measurement ───────────────────────────────────────────────────
var _last_tick_us: int = 0

# ── Live counters ─────────────────────────────────────────────────────────────
var _fire_count: int = 0 # Maintained incrementally — no O(n) scan needed

# ── Signals ───────────────────────────────────────────────────────────────────
signal grid_updated(front_buffer: Array)
signal cell_burned_out(grid_pos: Vector2i)
signal cell_extinguished(grid_pos: Vector2i)


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	var vp := get_viewport_rect().size
	cell_w = vp.x / float(COLS)
	cell_h = vp.y / float(ROWS)
	_init_buffers()
	_rb_registry = []


func _init_buffers() -> void:
	var n := COLS * ROWS
	_grid = []
	_grid.resize(n)
	_visited = PackedByteArray()
	_visited.resize(n)
	_visited.fill(0)
	var i := 0
	while i < n:
		_grid[i] = CACell.new()
		i += 1


# ── Main update ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum >= TICK_RATE:
		_tick_accum -= TICK_RATE
		_run_tick()


func _run_tick() -> void:
	var t_start := Time.get_ticks_usec()

	# Step 1: Stamp RigidBody2D positions into the grid.
	_sync_rigidbodies()

	# Step 2: Reset visited mask — PackedByteArray.fill() is a C-level memset,
	#         essentially free compared to the old 10,000-object _clear_back().
	_visited.fill(0)

	# Step 3: Process cells bottom-to-top (gravity order).
	#         While loops avoid the Array allocation that range() produces.
	var row := ROWS - 1
	while row >= 0:
		var col := 0
		while col < COLS:
			_process_cell(col, row)
			col += 1
		row -= 1

	_tick_count += 1
	_last_tick_us = Time.get_ticks_usec() - t_start

	# Emit so CARenderer and CABenchmark update.
	grid_updated.emit(_grid)


# ── Cell rule dispatch ────────────────────────────────────────────────────────
func _process_cell(col: int, row: int) -> void:
	var idx := row * COLS + col # inlined _idx — avoids function call overhead

	# Fast-path: skip already-visited cells (moved/written this tick).
	if _visited[idx]:
		return

	var cell: CACell = _grid[idx]

	# Fast-path: EMPTY has no rules — skip ~70% of cells immediately.
	if cell.type == CellState.Type.EMPTY:
		return

	# Mark this cell visited before any rule fires.
	_visited[idx] = 1

	match cell.type:
		CellState.Type.FIRE:
			_rule_fire(col, row, idx, cell)
		CellState.Type.WATER:
			_rule_water(col, row, idx, cell)
		CellState.Type.SMOKE:
			_rule_smoke(col, row, idx, cell)
		CellState.Type.STEAM:
			_rule_steam(col, row, idx, cell)
		CellState.Type.WOOD:
			_rule_wood(col, row, idx, cell)
		# METAL: no rule — stays put.


# ── FIRE rules ────────────────────────────────────────────────────────────────
const FIRE_LIFETIME: int = 45
const FIRE_SPREAD_PROB: float = 0.55

func _rule_fire(col: int, row: int, idx: int, cell: CACell) -> void:
	cell.lifetime += 1

	# Age out → become EMPTY, spawn SMOKE above.
	if cell.lifetime >= FIRE_LIFETIME:
		cell.type = CellState.Type.EMPTY
		cell.lifetime = 0
		_fire_count -= 1
		if _in_bounds(col, row - 1):
			var ai := (row - 1) * COLS + col
			var above: CACell = _grid[ai]
			if above.type == CellState.Type.EMPTY and not _visited[ai]:
				above.type = CellState.Type.SMOKE
				above.lifetime = 0
				_visited[ai] = 1
		cell_burned_out.emit(Vector2i(col, row))
		return

	# Rise into an empty cell above.
	if _in_bounds(col, row - 1):
		var ai := (row - 1) * COLS + col
		var above: CACell = _grid[ai]
		if above.type == CellState.Type.EMPTY and not _visited[ai]:
			_move_cell(idx, ai, cell, above)
			return

	# Spread heat to adjacent WOOD / extinguish with WATER.
	var neighbours := [
		Vector2i(col - 1, row), Vector2i(col + 1, row),
		Vector2i(col, row + 1), Vector2i(col - 1, row - 1),
		Vector2i(col + 1, row - 1),
	]
	for nb in neighbours:
		if not _in_bounds(nb.x, nb.y):
			continue
		var ni = nb.y * COLS + nb.x
		var nb_cell: CACell = _grid[ni]
		if nb_cell.type == CellState.Type.WOOD:
			nb_cell.heat += 1
			if nb_cell.heat >= CellState.IGNITION_TICKS[CellState.Type.WOOD]:
				if randf() < FIRE_SPREAD_PROB:
					nb_cell.type = CellState.Type.FIRE
					nb_cell.heat = 0
					_visited[ni] = 1
					_fire_count += 1
		elif nb_cell.type == CellState.Type.WATER:
			# Fire meets water: extinguish both, produce steam.
			cell.type = CellState.Type.EMPTY
			_fire_count -= 1
			nb_cell.type = CellState.Type.STEAM
			_visited[ni] = 1
			cell_extinguished.emit(Vector2i(col, row))
			return


# ── WATER rules ───────────────────────────────────────────────────────────────
func _rule_water(col: int, row: int, idx: int, cell: CACell) -> void:
	# Fall straight down.
	if _in_bounds(col, row + 1):
		var bi := (row + 1) * COLS + col
		var below: CACell = _grid[bi]
		if below.type == CellState.Type.EMPTY and not _visited[bi]:
			_move_cell(idx, bi, cell, below)
			return
		# Fall diagonally.
		var dir: int = 1 if randf() > 0.5 else -1
		for d in [dir, -dir]:
			if _in_bounds(col + d, row + 1):
				var di = (row + 1) * COLS + col + d
				var diag: CACell = _grid[di]
				if diag.type == CellState.Type.EMPTY and not _visited[di]:
					_move_cell(idx, di, cell, diag)
					return

	# Spread sideways.
	var dir: int = 1 if randf() > 0.5 else -1
	for d in [dir, -dir]:
		if _in_bounds(col + d, row):
			var si = row * COLS + col + d
			var side: CACell = _grid[si]
			if side.type == CellState.Type.EMPTY and not _visited[si]:
				_move_cell(idx, si, cell, side)
				return


# ── WOOD rules ────────────────────────────────────────────────────────────────
func _rule_wood(col: int, row: int, idx: int, cell: CACell) -> void:
	# Heat accumulation is handled by FIRE's spread rule.
	# Here we catch any threshold crossing that wasn't yet consumed.
	if cell.heat >= CellState.IGNITION_TICKS[CellState.Type.WOOD]:
		cell.type = CellState.Type.FIRE
		cell.heat = 0
		_fire_count += 1
		_visited[idx] = 1


# ── SMOKE rules ───────────────────────────────────────────────────────────────
const SMOKE_LIFETIME: int = 90

func _rule_smoke(col: int, row: int, idx: int, cell: CACell) -> void:
	cell.lifetime += 1
	if cell.lifetime >= SMOKE_LIFETIME:
		cell.type = CellState.Type.EMPTY
		cell.lifetime = 0
		return
	# Rise.
	if _in_bounds(col, row - 1):
		var ai := (row - 1) * COLS + col
		var above: CACell = _grid[ai]
		if above.type == CellState.Type.EMPTY and not _visited[ai]:
			_move_cell(idx, ai, cell, above)
			return
	# Drift sideways-upward.
	var dir := 1 if randf() > 0.5 else -1
	if _in_bounds(col + dir, row - 1):
		var di := (row - 1) * COLS + col + dir
		var diag: CACell = _grid[di]
		if diag.type == CellState.Type.EMPTY and not _visited[di]:
			_move_cell(idx, di, cell, diag)


# ── STEAM rules ───────────────────────────────────────────────────────────────
const STEAM_LIFETIME: int = 50

func _rule_steam(col: int, row: int, idx: int, cell: CACell) -> void:
	cell.lifetime += 1
	if cell.lifetime >= STEAM_LIFETIME:
		cell.type = CellState.Type.EMPTY
		cell.lifetime = 0
		return
	# Rise quickly.
	for step in [1, 2]:
		if _in_bounds(col, row - step):
			var ai = (row - step) * COLS + col
			var above: CACell = _grid[ai]
			if above.type == CellState.Type.EMPTY and not _visited[ai]:
				_move_cell(idx, ai, cell, above)
				return
	# Drift sideways.
	var dir := 1 if randf() > 0.5 else -1
	if _in_bounds(col + dir, row):
		var si := row * COLS + col + dir
		var side: CACell = _grid[si]
		if side.type == CellState.Type.EMPTY and not _visited[si]:
			_move_cell(idx, si, cell, side)


# ── Move helper ───────────────────────────────────────────────────────────────
# Copies src data into dst in the single buffer, resets src to EMPTY.
# Marks both as visited so neither is processed again this tick.
func _move_cell(src_idx: int, dst_idx: int, src: CACell, dst: CACell) -> void:
	dst.type = src.type
	dst.heat = src.heat
	dst.lifetime = src.lifetime
	_visited[dst_idx] = 1

	src.type = CellState.Type.EMPTY
	src.heat = 0
	src.lifetime = 0
	# src is already marked visited (done before calling the rule).


# ── Spatial index ─────────────────────────────────────────────────────────────
func register_body(body: RigidBody2D) -> void:
	if not body in _rb_registry:
		_rb_registry.append(body)


func unregister_body(body: RigidBody2D) -> void:
	_rb_registry.erase(body)


func _sync_rigidbodies() -> void:
	for body in _rb_registry:
		if not is_instance_valid(body):
			continue
		var gp := world_to_grid(body.global_position)
		if not _in_bounds(gp.x, gp.y):
			continue
		var cell: CACell = _grid[gp.y * COLS + gp.x]
		var old_type := cell.type
		if body is HeatSource:
			cell.type = CellState.Type.FIRE
		elif body is Flammable:
			cell.type = CellState.Type.WOOD
		elif body is Extinguisher:
			cell.type = CellState.Type.WATER
		elif body is Conductor:
			cell.type = CellState.Type.METAL
		# Keep fire counter consistent.
		if old_type != CellState.Type.FIRE and cell.type == CellState.Type.FIRE:
			_fire_count += 1
		elif old_type == CellState.Type.FIRE and cell.type != CellState.Type.FIRE:
			_fire_count -= 1


# ── Bounds check ──────────────────────────────────────────────────────────────
func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS


# ── Public API: paint cells ───────────────────────────────────────────────────
func paint_cell(world_pos: Vector2, type: int) -> void:
	var gp := world_to_grid(world_pos)
	if _in_bounds(gp.x, gp.y):
		var idx := gp.y * COLS + gp.x
		var cell: CACell = _grid[idx]
		var old_type := cell.type
		cell.type = type
		cell.heat = 0
		cell.lifetime = 0
		if old_type != CellState.Type.FIRE and type == CellState.Type.FIRE:
			_fire_count += 1
		elif old_type == CellState.Type.FIRE and type != CellState.Type.FIRE:
			_fire_count -= 1


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


# ── Debug API ─────────────────────────────────────────────────────────────────
func get_tick_time_us() -> int:
	return _last_tick_us

func get_tick_count() -> int:
	return _tick_count

func get_fire_count() -> int:
	return _fire_count
