extends Node2D
## Tracks which room the player is in, tints the rooms, and keeps the camera inside the current room.
##   grey  = nobody in the room
##   green = you're in the room
##   blue  = you're in the room with "Finding Friends" switched on

const TILE := 16

const COLOR_EMPTY := Color(0.45, 0.45, 0.45, 0.45)
const COLOR_ME := Color(0.2, 0.9, 0.3, 0.35)
const COLOR_FRIENDS := Color(0.2, 0.45, 1.0, 0.4)

# Room rectangles in world pixels. The hallway uses the camera limits you set (0..910 x 0..143).
# Each door room: 9 tiles of floor + 2 tiles of back wall, centred on its door (door tiles x = 8, 19, 35).
var rooms := [
	{"name": "Hallway", "rect": Rect2(0, 0, 910, 143), "tint": false},
	{"name": "Room 1", "rect": Rect2(4 * TILE, -8 * TILE, 9 * TILE, 8 * TILE), "tint": true},
	{"name": "Room 2", "rect": Rect2(15 * TILE, -8 * TILE, 9 * TILE, 8 * TILE), "tint": true},
	{"name": "Room 3", "rect": Rect2(31 * TILE, -8 * TILE, 9 * TILE, 8 * TILE), "tint": true},
]

var finding_friends := false
var current_room := -1
var base_zoom := Vector2.ONE  # the zoom set on the player's Camera2D (used in the hallway)
var zoom_tween: Tween

@onready var player: CharacterBody2D = $Node2D/CharacterBody2D
@onready var camera: Camera2D = $Node2D/CharacterBody2D/Camera2D
@onready var feet: CollisionShape2D = $Node2D/CharacterBody2D/CollisionShape2D
@onready var friends_button: Button = $UI/FindingFriendsButton


func _ready() -> void:
	camera.make_current()
	camera.limit_smoothed = true
	base_zoom = camera.zoom
	get_viewport().size_changed.connect(_apply_camera_limits)

	var all := Rect2(rooms[0].rect)
	for room in rooms:
		all = all.merge(room.rect)
		if room.tint:
			_add_side_walls(room.rect)
			_add_overlay(room)
	player.bounds = all

	friends_button.toggled.connect(_on_friends_toggled)
	_on_friends_toggled(friends_button.button_pressed)

	_update_room(true)


func _physics_process(_delta: float) -> void:
	_update_room(false)


func _update_room(force: bool) -> void:
	var idx := current_room
	for i in rooms.size():
		if rooms[i].rect.has_point(feet.global_position):
			idx = i
			break
	if idx == current_room and not force:
		return
	current_room = idx
	_apply_camera_limits()
	_refresh_colors()
	if force:
		camera.reset_smoothing()


func _apply_camera_limits() -> void:
	if current_room < 0:
		return
	var r: Rect2 = rooms[current_room].rect
	# Lock the camera to exactly this room.
	camera.limit_left = int(ceil(r.position.x))
	camera.limit_top = int(ceil(r.position.y))
	camera.limit_right = int(floor(r.end.x))
	camera.limit_bottom = int(floor(r.end.y))
	# Zoom in just enough that the room fills the screen, so nothing outside it shows.
	var screen := get_viewport_rect().size
	var z: float = max(base_zoom.x, screen.x / r.size.x, screen.y / r.size.y)
	if zoom_tween:
		zoom_tween.kill()
	zoom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	zoom_tween.tween_property(camera, "zoom", Vector2(z, z), 0.35)


func _refresh_colors() -> void:
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		if not room.tint:
			continue
		var c := COLOR_EMPTY
		if i == current_room:
			c = COLOR_FRIENDS if finding_friends else COLOR_ME
		room.overlay.color = c


func _on_friends_toggled(on: bool) -> void:
	finding_friends = on
	friends_button.text = "Finding Friends: ON" if on else "Finding Friends: OFF"
	_refresh_colors()


func _add_overlay(room: Dictionary) -> void:
	var overlay := ColorRect.new()
	overlay.name = room.name + "Tint"
	overlay.position = room.rect.position
	overlay.size = room.rect.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = COLOR_EMPTY
	add_child(overlay)
	move_child(overlay, $Node2D.get_index())  # draw under the player
	room.overlay = overlay


func _add_side_walls(r: Rect2) -> void:
	var body := StaticBody2D.new()
	add_child(body)
	for x in [r.position.x - TILE, r.end.x]:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(TILE, r.size.y)
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(x + TILE / 2.0, r.position.y + r.size.y / 2.0)
		body.add_child(col)
