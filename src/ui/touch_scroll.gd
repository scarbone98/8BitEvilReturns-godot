class_name TouchScroll
extends ScrollContainer
## A vertical list you can drag with a finger anywhere on it, phone style,
## with a little fling when you let go. Godot's own drag-scroll only starts
## when the touch lands on empty space, and a button under the finger keeps
## the touch, so dragging a list of buttons pressed one instead. Here a drag
## past DEADZONE cancels that press, so scrolling never buys or picks.

const DEADZONE := 6.0
const FRICTION := 6.0  # how fast a fling slows down (per second)

var _touch := -1
var _start := Vector2.ZERO
var _start_scroll := 0.0
var _dragging := false
var _last_y := 0.0
var _last_t := 0
var _velocity := 0.0

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = 100000  # turn off the built-in drag so the two never fight

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and get_global_rect().has_point(event.position):
			_touch = event.index
			_start = event.position
			_start_scroll = scroll_vertical
			_dragging = false
			_velocity = 0.0
			_last_y = event.position.y
			_last_t = Time.get_ticks_msec()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		var dy: float = event.position.y - _start.y
		if not _dragging and absf(dy) > DEADZONE:
			_dragging = true
			_cancel_presses(self)
		if _dragging:
			scroll_vertical = int(_start_scroll - dy)
			var now := Time.get_ticks_msec()
			var dt := maxf(0.001, (now - _last_t) / 1000.0)
			_velocity = lerpf(_velocity, -(event.position.y - _last_y) / dt, 0.5)
			_last_y = event.position.y
			_last_t = now
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _touch != -1 or absf(_velocity) < 10.0:
		_velocity = 0.0 if _touch == -1 else _velocity
		return
	scroll_vertical = int(scroll_vertical + _velocity * delta)
	_velocity *= maxf(0.0, 1.0 - FRICTION * delta)

## Disabling a button clears the press it's holding, so the finger lifting
## later doesn't click it. It's switched straight back on.
func _cancel_presses(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton and not c.disabled:
			c.disabled = true
			c.disabled = false
		_cancel_presses(c)
