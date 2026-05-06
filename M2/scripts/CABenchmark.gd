# CABenchmark.gd
# Measures and displays M2 performance metrics in real time.
#
# Evaluation criterion (from milestone spec):
#   "CA grid update completes within 1.5ms per tick at 60Hz
#    with fire covering 50% of grid."
#
# Live HUD shows:
#   - Tick time (us → ms)  with Pass/Fail verdict
#   - FPS
#   - Fire cell count and % coverage
class_name CABenchmark
extends Label

# Assigned by M2Main._ready()
var _grid : CAGrid = null

const AVERAGE_WINDOW : int = 30
const CRITERION_US   : int = 1500   # 1.5 ms

var _tick_samples : Array[int] = []
var _fire_count   : int = 0


func _ready() -> void:
	add_theme_font_size_override("font_size", 14)


func _on_grid_updated(front_buffer: Array) -> void:
	if not _grid:
		return

	# Sample this tick's time.
	var sample := _grid.get_tick_time_us()
	_tick_samples.append(sample)
	if _tick_samples.size() > AVERAGE_WINDOW:
		_tick_samples.pop_front()

	# Count fire cells.
	_fire_count = 0
	for cell : CACell in front_buffer:
		if cell.type == CellState.Type.FIRE:
			_fire_count += 1

	_update_display()


func _update_display() -> void:
	var avg_us : float = 0.0
	for s in _tick_samples:
		avg_us += s
	if _tick_samples.size() > 0:
		avg_us /= _tick_samples.size()

	var avg_ms    : float  = avg_us / 1000.0
	var fire_pct  : float  = float(_fire_count) / float(CAGrid.COLS * CAGrid.ROWS) * 100.0
	var fps       : float  = Engine.get_frames_per_second()
	var verdict   : String = "✅ PASS" if avg_us <= CRITERION_US else "❌ FAIL"

	text = (
		"── M2 CA Benchmark ──\n"
		+ "Tick:  %.2f ms  %s\n" % [avg_ms, verdict]
		+ "Crit:  ≤ 1.50 ms @ 60 Hz\n"
		+ "FPS:   %.0f\n" % fps
		+ "Fire:  %d cells (%.1f%%)\n" % [_fire_count, fire_pct]
		+ "Ticks: %d" % _grid.get_tick_count()
	)

	modulate = Color(0.2, 1.0, 0.3) if avg_us <= CRITERION_US else Color(1.0, 0.3, 0.2)
