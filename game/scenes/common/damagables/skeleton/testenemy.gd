
extends KinematicBody2D

# member variables here, example:
# var a=2
# var b="textvar"
var MOVESPEED = 3
var collision_rect
var solid_rect
var accel = 1
var TILESIZE = 32
var sprite_offset
var direction = 1
var falling = false
var is_dying = false
var is_hurt = false
var animation_player
var current_animation = "walk"
var player
var hpclass = preload("res://gui/hud/hp.scn")
var hud
var hp = 1
var hurt_delay = 10
var current_delay = 0
var walk_delay = 60
var current_walk_delay = 0
var floortile_check_requested = false
var frozen = false
const FREEZE_DELAY = 300
var freeze_counter = 0
var freezeblock = preload("res://scenes/common/iceblock.scn")
var freezeblock_obj
var stun = preload("res://scenes/common/stun.scn")
var stun_obj
var stun_delay = 300
var stun_current_delay = 0
var is_stunned = false

func check_dying():
	if (hp <= 0):
		is_stunned = false
		if (stun_obj != null):
			stun_obj.hide()
		is_dying = true
		is_hurt = false
		if (has_node("damagable")):
			remove_child(get_node("damagable"))

func request_stun():
	if (stun_obj != null):
		is_stunned = true
		stun_obj.show()
		stun_obj.get_node("AnimationPlayer").play("rotate")

func check_motion(frontX, space_state):
	if (!is_dying && !frozen):
		if(current_delay == 0):
			var damageTiles = collision_rect.get_overlapping_areas()
			for i in damageTiles:
				var collider
				if (i.has_node("weapon")):
					collider = i.get_node("weapon")
					player.get_node("player").set("hit_enemy", true)
				if (i.has_node("magic")):
					# freeze in collision block if hit with an ice attack
					if (i.get_parent() != null && i.get_parent().get_name() == "Ice"):
						frozen = true
						add_child(freezeblock_obj)
						if (has_node(collision_rect.get_name())):
							remove_child(collision_rect)
					collider = i.get_node("magic")
					var hp = i.get_parent().get("hp")
					if (hp != null):
						i.get_parent().set("hp", hp - 1)
				if (collider != null):
					var hp_obj = hpclass.instance()
					hud.add_child(hp_obj)
					var hitpos = hp_obj.calculate_hitpos(i.get_global_pos(), collider.get_shape().get_extents(), get_pos(), sprite_offset)
					hp -= 1
					is_hurt = true
					check_dying()
					# TODO - calculate damage helper method
					hp_obj.display_damage(hitpos, 1)
					current_delay += 1
					current_walk_delay += 1
	
		if (!is_hurt && !is_stunned):
			var frontTile = space_state.intersect_ray(Vector2(frontX, get_global_pos().y - sprite_offset.y), Vector2(frontX, get_global_pos().y + sprite_offset.y - 1))
		
			if (frontTile != null && frontTile.has("position")):
				direction = direction * -1
			
			frontTile = space_state.intersect_ray(Vector2(frontX + direction*MOVESPEED, get_global_pos().y + sprite_offset.y), Vector2(frontX + direction*MOVESPEED, get_global_pos().y + sprite_offset.y + TILESIZE))
			if (frontTile == null || !frontTile.has("position")):
				direction = direction * -1
			if (frontTile != null && frontTile.has("collider")):
				var collider = frontTile["collider"]
				if (collider.get_name() == "player" && collider.get_global_pos().y - collider["sprite_offset"].y > get_global_pos().y + sprite_offset.y):
					direction = direction * -1
			
			move(Vector2(MOVESPEED * direction, 0))
	elif (frozen):
		freeze_counter += 1
		# flash to warn player that frozen state is almost over
		if (fmod(freeze_counter, 4) == 0 && float(freeze_counter)/FREEZE_DELAY > 0.75):
			freezeblock_obj.set_opacity(0)
		else:
			freezeblock_obj.set_opacity(1)
		if (freeze_counter >= FREEZE_DELAY):
			frozen = false
			freeze_counter = 0
			if (has_node(freezeblock_obj.get_name())):
				remove_child(freezeblock_obj)
			add_child(collision_rect)
			animation_player.play(current_animation)
	if (is_stunned):
		stun_current_delay += 1
		# flash to warn stun is almost over
		if (fmod(stun_current_delay, 4) == 0 && float(stun_current_delay)/stun_delay > 0.75):
			stun_obj.set_opacity(0)
		else:
			stun_obj.set_opacity(1)
		if (stun_current_delay >= stun_delay):
			is_stunned = false
			stun_current_delay = 0
			stun_obj.hide()
			stun_obj.get_node("AnimationPlayer").stop()
			animation_player.play(current_animation)

func step_vertical(frontX, space_state):
	if (!frozen):
		var desiredY = accel
		
		if (falling):
			desiredY += 1
		else:
			desiredY = 1
	
		desiredY = floortile_check(frontX, space_state, desiredY)
		
		var damageTiles = collision_rect.get_overlapping_areas()
		for i in damageTiles:
			if (i.has_node("weapon") && !floortile_check_requested):
				desiredY = 0
				floortile_check_requested = true
	
		move(Vector2(0, desiredY))

func floortile_check(frontX, space_state, desiredY):
	var blacklist = [player.get_node("player")]
	if (freezeblock_obj != null):
		blacklist.append(freezeblock_obj)
	var floorTile = space_state.intersect_ray(Vector2(frontX, get_global_pos().y + sprite_offset.y), Vector2(frontX, get_global_pos().y + sprite_offset.y + desiredY), blacklist)

	falling = true

	var closestTileY = desiredY
	
	if (floorTile != null && floorTile.has("position")):
		closestTileY = floorTile["position"].y 
		closestTileY -= get_global_pos().y + sprite_offset.y
		closestTileY = int(closestTileY)
	
		if (closestTileY == 0):
			falling = false

		if (abs(desiredY) < abs(closestTileY)):
			falling = true
			#accel = 0
	accel = min(abs(desiredY), abs(closestTileY))
	return closestTileY

func check_animation(new_animation):
	if (is_dying):
		new_animation = "die"
	if (is_hurt):
		new_animation = "hurt"
	return new_animation

func die():
	queue_free()

func _fixed_process(delta):
	var space = get_world_2d().get_space()
	var space_state = Physics2DServer.space_get_direct_state(space)

	var frontX = get_global_pos().x + direction * sprite_offset.x

	check_motion(frontX, space_state)
	
	step_vertical(frontX, space_state)
	
	var new_animation = "walk"
	
	new_animation = check_animation(new_animation)
	
	get_node(new_animation).set_scale(Vector2(direction, 1))
	
	if (current_delay > 0):
		current_delay += 1
		if (current_delay >= hurt_delay):
			current_delay = 0
	
	if (new_animation != current_animation):
		animation_player.play(new_animation)
		current_animation = new_animation
		
	if (frozen || is_stunned):
		animation_player.stop()
	
	if (is_hurt && !animation_player.is_playing()):
		is_hurt = false
	
	if (is_dying && !animation_player.is_playing()):
		die()

func _ready():
	collision_rect = get_node("damagable")
	solid_rect = get_node("CollisionShape2D")
	sprite_offset = get_node("damagable/CollisionShape2D").get_shape().get_extents()
	animation_player = get_node("AnimationPlayer")
	player = get_tree().get_root().get_node("world/playercontainer")
	hud = get_tree().get_root().get_node("world/gui/hpcontainer")
	set_fixed_process(true)
	freezeblock_obj = freezeblock.instance()
	freezeblock_obj.set_scale(Vector2(sprite_offset.x * 2 / TILESIZE, sprite_offset.y * 2 / TILESIZE))
	stun_obj = get_node("Stun")
	if (stun_obj != null):
		stun_obj.hide()