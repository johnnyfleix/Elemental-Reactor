# CARenderer.gd
# Converts the CA grid's front buffer into a visible texture every tick.
#
# PERFORMANCE APPROACH — set_data() bulk write + pre-baked RGBA bytes:
#   • set_data() = one bulk memcpy to GPU, replaces 10,000 set_pixel() calls.
#   • _base_rgba[type] = pre-baked PackedByteArray(4) per type so the hot loop
#     does no Color object creation and no float→byte math per static cell.
#   • while loops instead of range() avoid per-call Array allocation.
#   • Per-cell effects (fire flicker, smoke fade) use integer arithmetic only.
#
# The TextureRect is drawn ABOVE the CA texture so M1 sprites sit on top.
class_name CARenderer
extends Node2D

@onready var _texture : TextureRect = $TextureRect

# Assigned by M2Main._ready() after all nodes are ready.
var _grid  : CAGrid = null

var _image     : Image
var _tex       : ImageTexture
var _byte_buf  : PackedByteArray   # Reused every tick — no GC allocation

# Pre-baked RGBA bytes per cell type: _base_rgba[type] = [r,g,b,a] as ints.
# Built once in _setup_texture(). The hot loop reads these with plain [] access.
var _base_rgba: Array  # Array[Array[int]] — indexed by CellState.Type value

# Cached type constants (avoids repeated enum lookup in the hot loop).
var _TYPE_FIRE  : int
var _TYPE_SMOKE : int
var _TYPE_STEAM : int


func _ready() -> void:
	_setup_texture()


func _setup_texture() -> void:
	var vp := get_viewport_rect().size
	_texture.size = vp

	# Pre-allocate the byte buffer: COLS * ROWS * 4 bytes (R, G, B, A per cell).
	# Reused every tick — avoids allocating 40 KB of garbage per frame.
	var total_cells := CAGrid.COLS * CAGrid.ROWS
	_byte_buf = PackedByteArray()
	_byte_buf.resize(total_cells * 4)

	_image = Image.create(CAGrid.COLS, CAGrid.ROWS, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)

	_tex = ImageTexture.create_from_image(_image)
	_texture.texture = _tex
	_texture.stretch_mode = TextureRect.STRETCH_SCALE

	# Pre-bake RGBA bytes for every static cell type.
	_base_rgba = []
	for c in CellState.COLOURS:
		_base_rgba.append([
			int(c.r * 255), int(c.g * 255),
			int(c.b * 255), int(c.a * 255)
		])

	# Cache type constants so the hot loop accesses locals, not CellState each time.
	_TYPE_FIRE  = CellState.Type.FIRE
	_TYPE_SMOKE = CellState.Type.SMOKE
	_TYPE_STEAM = CellState.Type.STEAM


func _on_grid_updated(front_buffer: Array) -> void:
	# Single pass: write all cell colours into the byte buffer.
	# Then one set_data() call pushes everything to the GPU at once.
	#
	# Hot-loop design:
	#   • _base_rgba gives us pre-baked [r,g,b,a] per type with no float math.
	#   • While loop avoids per-call Array allocation of range().
	#   • Per-effect overrides use integer-only arithmetic.
	var buf_i   := 0
	var cell_i  := 0
	var n       := CAGrid.COLS * CAGrid.ROWS
	var fire    := _TYPE_FIRE
	var smoke   := _TYPE_SMOKE
	var steam   := _TYPE_STEAM
	var smoke_lt := CAGrid.SMOKE_LIFETIME
	var steam_lt := CAGrid.STEAM_LIFETIME

	while cell_i < n:
		var cell : CACell = front_buffer[cell_i]
		var t    : int    = cell.type
		var rgba : Array  = _base_rgba[t]

		if t == fire:
			# Flicker: cheap triangle wave on alpha avoids trig entirely.
			# Maps lifetime 0..44 to an alpha oscillation between 128 and 255.
			var ph : int = cell.lifetime % 16
			var a  : int = 128 + (ph if ph < 8 else 16 - ph) * 16
			_byte_buf[buf_i]     = rgba[0]
			_byte_buf[buf_i + 1] = rgba[1]
			_byte_buf[buf_i + 2] = rgba[2]
			_byte_buf[buf_i + 3] = a
		elif t == smoke:
			# Fade: integer multiply then right-shift avoids float division.
			var a : int = rgba[3] * (smoke_lt - cell.lifetime) / smoke_lt
			_byte_buf[buf_i]     = rgba[0]
			_byte_buf[buf_i + 1] = rgba[1]
			_byte_buf[buf_i + 2] = rgba[2]
			_byte_buf[buf_i + 3] = a
		elif t == steam:
			var a : int = rgba[3] * (steam_lt - cell.lifetime) / steam_lt
			_byte_buf[buf_i]     = rgba[0]
			_byte_buf[buf_i + 1] = rgba[1]
			_byte_buf[buf_i + 2] = rgba[2]
			_byte_buf[buf_i + 3] = a
		else:
			# Static types (EMPTY, WOOD, WATER, METAL): read pre-baked bytes.
			_byte_buf[buf_i]     = rgba[0]
			_byte_buf[buf_i + 1] = rgba[1]
			_byte_buf[buf_i + 2] = rgba[2]
			_byte_buf[buf_i + 3] = rgba[3]

		buf_i  += 4
		cell_i += 1

	# Single GPU upload — this replaces 10,000 set_pixel() calls.
	_image.set_data(CAGrid.COLS, CAGrid.ROWS, false, Image.FORMAT_RGBA8, _byte_buf)
	_tex.update(_image)
