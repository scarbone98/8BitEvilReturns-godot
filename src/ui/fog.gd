extends ColorRect
## Nightmare's blizzard (white snow fog) and Lights Out (darkness): the screen
## is covered except soft lit circles round each hero (and, in the dark,
## round the candelabras). Drawn on every player's own screen, under the HUD.

const SHADER := """
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);
uniform vec2 size = vec2(240.0, 400.0);
uniform int count = 0;
uniform vec4 lights[16];   // x, y (screen), radius
uniform float t = 0.0;
uniform bool snow = false;
void fragment() {
	vec2 p = UV * size;
	float a = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) break;
		float d = distance(p, lights[i].xy);
		a = min(a, smoothstep(lights[i].z * 0.5, lights[i].z, d));
	}
	// Chunky steps and a 2px ordered dither, so the edge looks pixel-art.
	vec2 cell = floor(p / 2.0);
	float dither = mod(cell.x + cell.y * 2.0, 4.0) / 4.0;
	a = clamp(floor(a * 4.0 + dither) / 4.0, 0.0, 1.0);
	vec4 c = vec4(fog_color.rgb, fog_color.a * a);
	if (snow) {
		vec2 q = floor((p + vec2(t * 40.0, t * 70.0)) / 2.0);
		float flake = step(0.992, fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453));
		c = mix(c, vec4(1.0, 1.0, 1.0, 0.85), flake);
	}
	COLOR = c;
}
"""

var run
var kind := ""  # "blizzard" or "darkness"
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	material.shader = sh
	if kind == "blizzard":
		material.set_shader_parameter("fog_color", Color(0.86, 0.9, 1.0, 0.88))
		material.set_shader_parameter("snow", true)
	else:
		material.set_shader_parameter("fog_color", Color(0.02, 0.0, 0.05, 0.94))

func _process(delta: float) -> void:
	_t += delta
	var view := size
	var half := view * 0.5
	var cam: Vector2 = run.camera.position
	var lights: Array = []
	# The blizzard gusts: every 45s it closes right in for a few seconds.
	var hero_r := 95.0
	if kind == "blizzard":
		var g := fmod(run.time, 45.0)
		hero_r = 120.0 if g < 33.0 else lerpf(120.0, 70.0, clampf((g - 33.0) / 2.0, 0.0, 1.0) * clampf((45.0 - g) / 2.0, 0.0, 1.0))
	for h in run.heroes.values():
		if not h.dead:
			lights.append(Vector4(half.x + h.position.x - cam.x, half.y + h.position.y - cam.y - 6.0, hero_r, 0.0))
	if kind == "darkness":
		for o in run.obstacles.props_in(Rect2(cam - half - Vector2(60, 60), view + Vector2(120, 120))):
			if o.kind == "prop_candelabra" and lights.size() < 16:
				var flick := 52.0 + sin(_t * 9.0 + o.pos.x) * 3.0
				lights.append(Vector4(half.x + o.pos.x - cam.x, half.y + o.pos.y - cam.y - 14.0, flick, 0.0))
	var packed: Array = []
	for k in 16:
		packed.append(lights[k] if k < lights.size() else Vector4.ZERO)
	material.set_shader_parameter("size", view)
	material.set_shader_parameter("count", mini(lights.size(), 16))
	material.set_shader_parameter("lights", packed)
	material.set_shader_parameter("t", _t)
