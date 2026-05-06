# CARenderer.gd
# Converts the CA grid's front buffer into a visible texture every tick.
#
# PERFORMANCE APPROACH — set_data() bulk write:
#   Instead of calling set_pixel() 10,000 times per tick (which was causing
#   the 17ms tick time), we build a raw PackedByteArray of RGBA values in
#   one GDScript loop, then push it to the GPU in a single set_data() call.
#
#   set_pixel()  = 10,000 individual GDScript→C++ calls per tick  → ~17ms
#   set_data()   = 1 bulk memcpy to GPU                           → ~0.3ms
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


func _ready() -> void:
	_setup_texture()


func _setup_texture() -> void:
	var vp := get_viewport_rect().size
	_texture.size = vp

	# Pre-allocate the byte buffer: COLS * ROWS * 4 bytes (R, G, B, A per cell).
	# We reuse this buffer every tick — avoids allocating 40KB of garbage per frame.
	var total_cells := CAGrid.COLS * CAGrid.ROWS
	_byte_buf = PackedByteArray()
	_byte_buf.resize(total_cells * 4)

	_image = Image.create(CAGrid.COLS, CAGrid.ROWS, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)

	_tex = ImageTexture.create_from_image(_image)
	_texture.texture = _tex
	_texture.stretch_mode = TextureRect.STRETCH_SCALE


func _on_grid_updated(front_buffer: Array) -> void:
	# Single pass: write all cell colours into the byte buffer.
	# Then one set_data() call pushes everything to the GPU at once.
	var i := 0
	for idx in range(CAGrid.COLS * CAGrid.ROWS):
		var cell   : CACell = front_buffer[idx]
		var colour : Color  = CellState.COLOURS[cell.type]

		# Per-type visual effects — applied before writing bytes.
		if cell.type == CellState.Type.FIRE:
			# Flicker: modulate alpha using sine of lifetime.
			colour.a = 0.75 + 0.25 * sin(cell.lifetime * 0.6)

		elif cell.type == CellState.Type.SMOKE:
			# Fade out as smoke ages toward its lifetime limit.
			colour.a *= 1.0 - float(cell.lifetime) / float(CAGrid.SMOKE_LIFETIME)

		elif cell.type == CellState.Type.STEAM:
			colour.a *= 1.0 - float(cell.lifetime) / float(CAGrid.STEAM_LIFETIME)

		# Write RGBA bytes directly — no Color object allocation per pixel.
		_byte_buf[i]     = int(colour.r * 255)
		_byte_buf[i + 1] = int(colour.g * 255)
		_byte_buf[i + 2] = int(colour.b * 255)
		_byte_buf[i + 3] = int(colour.a * 255)
		i += 4

	# Single GPU upload — this replaces 10,000 set_pixel() calls.
	_image.set_data(CAGrid.COLS, CAGrid.ROWS, false, Image.FORMAT_RGBA8, _byte_buf)
	_tex.update(_image)
