extends CharacterBody2D
## Walks the player to your phone's location, received from OwnTracks via MQTT.
## Attach to the CharacterBody2D (it needs Sprite2D, AnimationPlayer, CollisionShape2D and Camera2D children).
## Uses the MQTT addon in res://addons/mqtt/
## Untick "Use GPS" in the Inspector to go back to plain arrow-key movement.
## With GPS on, the arrow keys still work too (handy for testing); the phone takes over again on its
## next new position.

@export var use_gps := true

const BROKER_URL := "tcp://test.mosquitto.org:1883"
const DEVICE_ID := "godot-hack-7391"          # must match "Device ID" in OwnTracks
const TOPIC := "owntracks/+/" + DEVICE_ID

# This real-world point = where you placed the player in the editor.
const ORIGIN_LAT := 45.495631
const ORIGIN_LON := -73.579097
const PIXELS_PER_METER := 96.0                 # world px per real metre (one floor tile = 16 px)

# Walking
const MIN_SPEED := 10.0                       # px/s
const MAX_SPEED := 600.0                      # px/s
const KEYBOARD_SPEED := 300.0                 # px/s with the arrow keys
# Your phone only gets a NEW position every few seconds (it repeats the old one in between).
# The player takes about as long as the last gap to walk to each new spot,
# so it keeps moving smoothly instead of dashing then standing still.
const MIN_ARRIVE_TIME := 1.0                  # seconds
const MAX_ARRIVE_TIME := 8.0                  # seconds
const ARRIVE_DISTANCE := 1.0                  # px: close enough, stop walking
const FLIP_WHEN_MOVING_RIGHT := true          # set false if your sprite faces right by default

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D
@onready var hitbox: CollisionShape2D = $CollisionShape2D

var bounds := Rect2()                          # set by world.gd: the hallway + all rooms

var mqtt
var map_origin: Vector2
var target_pos: Vector2
var walk_speed := MIN_SPEED
var has_fix := false
var last_change_time := 0.0                    # when the phone last reported a NEW position


func _ready() -> void:
	map_origin = global_position
	target_pos = global_position
	if not use_gps:
		return  # keyboard only: don't connect to the phone

	var mqtt_script = load("res://addons/mqtt/mqtt.gd")
	if mqtt_script == null:
		push_error("MQTT addon missing: res://addons/mqtt/mqtt.gd")
		return
	mqtt = mqtt_script.new()
	mqtt.verbose_level = 1
	add_child(mqtt)
	mqtt.broker_connected.connect(_on_connected)
	mqtt.broker_connection_failed.connect(func(): push_error("MQTT connection failed"))
	mqtt.received_message.connect(_on_message)
	mqtt.connect_to_broker(BROKER_URL)


func _on_connected() -> void:
	print("Connected to broker, listening on ", TOPIC)
	mqtt.subscribe(TOPIC)


func _on_message(_topic, message) -> void:
	var data = JSON.parse_string(str(message))
	if not (data is Dictionary and data.get("_type") == "location"):
		return

	var new_pos := _clamp_to_bounds(latlon_to_world(float(data.lat), float(data.lon)))
	var now := Time.get_ticks_msec() / 1000.0

	# First fix: appear there right away instead of walking across the map.
	if not has_fix:
		has_fix = true
		global_position = new_pos
		target_pos = new_pos
		last_change_time = now
		print("Location: ", data.lat, ", ", data.lon, " -> ", new_pos, "  (start)")
		return

	# Same spot repeated, or a tiny GPS wobble: keep walking to the current target.
	if new_pos.distance_to(target_pos) < PIXELS_PER_METER:
		print("Location: ", data.lat, ", ", data.lon, "  (no change)")
		return

	# Walk there over about the same time the phone took to give us this new spot.
	var arrive_time: float = clamp(now - last_change_time, MIN_ARRIVE_TIME, MAX_ARRIVE_TIME)
	last_change_time = now
	target_pos = new_pos
	walk_speed = clamp(global_position.distance_to(target_pos) / arrive_time, MIN_SPEED, MAX_SPEED)
	print("Location: ", data.lat, ", ", data.lon, " -> ", new_pos, "  (NEW, walking over %.1f s)" % arrive_time)


func _physics_process(_delta: float) -> void:
	var keys := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if keys or not use_gps:
		velocity = keys * KEYBOARD_SPEED
	else:
		var to_target := target_pos - global_position
		if to_target.length() > ARRIVE_DISTANCE:
			velocity = to_target.normalized() * walk_speed
		else:
			velocity = Vector2.ZERO

	var before := global_position
	move_and_slide()  # walls and doors still block / let you through
	global_position = _clamp_to_bounds(global_position)
	var moved := global_position - before

	if keys:
		target_pos = global_position  # don't get pulled back to the old phone spot
	elif moved.length() < 0.05 and velocity != Vector2.ZERO and get_slide_collision_count() > 0:
		target_pos = global_position  # blocked by a wall: stop pushing into it

	if moved.length() > 0.05:
		anim.play("new_animation23")
		# Face the walking direction (only on clear sideways movement, so it doesn't flicker).
		if abs(moved.x) > abs(moved.y) * 0.3:
			sprite.flip_h = (moved.x > 0) == FLIP_WHEN_MOVING_RIGHT
	else:
		anim.play("RESET")


# Turns lat/lon into a world position. Right = east, up = north.
# ORIGIN_LAT/LON lands where the player was placed in the editor.
func latlon_to_world(lat: float, lon: float) -> Vector2:
	var east_m := (lon - ORIGIN_LON) * 111320.0 * cos(deg_to_rad(ORIGIN_LAT))
	var north_m := (lat - ORIGIN_LAT) * 110540.0
	return map_origin + Vector2(east_m, -north_m) * PIXELS_PER_METER


# Keeps the player's hitbox inside `bounds` (falls back to the Camera2D limits if unset).
func _clamp_to_bounds(p: Vector2) -> Vector2:
	var area := bounds
	if not area.has_area():
		area = Rect2(camera.limit_left, camera.limit_top,
			camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)
	var half := Vector2.ZERO
	var offset := Vector2.ZERO
	if hitbox and hitbox.shape is RectangleShape2D:
		half = (hitbox.shape as RectangleShape2D).size * 0.5 * global_scale.abs()
		offset = hitbox.position * global_scale
	return p.clamp(area.position + half - offset, area.end - half - offset)
