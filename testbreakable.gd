
extends Node2D

# member variables here, example:
# var a=2
# var b="textvar"
var is_crumbling
var sound
var crumble_cycle = 0

func _fixed_process(delta):
	if (!is_crumbling):
		var tiles = get_node("KinematicBody2D/breakable").get_overlapping_areas()
		for i in tiles:
			if (i.has_node("weapon")):
				sound.set_volume_db(sound.play("crumble"), -10)
				is_crumbling = true
	else:
		get_node("KinematicBody2D/Sprite").set_opacity(0.5 + fmod(crumble_cycle, 4) * 0.3)
		crumble_cycle += 1
		if (!sound.is_active()):
			queue_free()

func _ready():
	# Initialization here
	sound = get_node("sound")
	set_fixed_process(true)


