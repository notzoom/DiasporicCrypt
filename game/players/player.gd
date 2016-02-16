
extends KinematicBody2D
# the great majority of player behavior and interaction implementation is modelled after this article: http://higherorderfun.com/blog/2012/05/20/the-guide-to-implementing-2d-platformers/comment-page-1
# please note that this blog link sometimes doesn't work, but you might still be able to see it through archive.org

const DEFAULT_GRAVITY = 1
# in order not to jump off 0-31 slopes, keep run speed below 10
const RUN_SPEED = 7
const JUMP_SPEED = 20
const TILE_SIZE = 32
const LADDER_SPEED = 5
const DAMAGE_THROWBACK = 10
const WATER = 0.5
const VERTICAL_DAMAGE_THROWBACK = 6
const HURT_GRACE_PERIOD = 60
const DEFAULT_FALL_HEIGHT = JUMP_SPEED * (JUMP_SPEED - 1)/2
# restrict vertical speed to prevent skipping and other weirdness
const SPEED_LIMIT = 30

var position = Vector2()
var current_animation = "idle"
var direction = 1
var falling = false
var accel = DEFAULT_GRAVITY
var sprite_offset = Vector2()
var tilemap
var collision
var animation_player
var jumpPressed = false
var hanging = false
var climbing_platform = false
var climb_platform = null
var climbspeed = 6
var on_ladder = false
var ladder_top = null
var is_crouching = false
var crouch_requested = false
var movingPlatform = null
var movingPlatformPos = null
var is_attacking = false
var attack_requested = false
var weapon
var weapon_collider
var weapon_offset = Vector2()
var weapon_collided = false
var attack_frame = 0
var damage_rect
var damageDelta = Vector2()
var is_hurt = false
var invulnerable = false
var hurt_grace_cycle = 0
var is_suspended = false
var current_gravity = DEFAULT_GRAVITY
var underwater = false
var fall_height = 0
var runspeed = RUN_SPEED
var jumpspeed = JUMP_SPEED
var defaultfallheight = DEFAULT_FALL_HEIGHT
var consumable
var blood_requested = false
var hit_enemy = false
var area2d_blacklist = []
var weapon_type = ""
# shared spells
var magic_spells = [{"id": "thunder", "auracolor": Color(1, 1, 1), "weaponcolor1": Color(1, 247/255.0, 138/255.0), "weaponcolor2": Color(0, 116/255.0, 1), "is_single": false, "charge": preload("res://players/magic/thunder/charge.scn"), "attack": preload("res://players/magic/thunder/thunder.scn"), "delay": true}, 
					{"id":"hex", "auracolor": Color(169/255.0, 0, 1), "weaponcolor1": Color(0, 0, 0), "weaponcolor2": Color(1, 0, 0), "is_single": false, "delay": true, "attack": preload("res://players/magic/hex/hex.scn")}, 
					{"id":"shield", "auracolor": Color(0, 0, 1), "weaponcolor1": Color(0, 55/255.0, 1), "weaponcolor2": Color(0, 208/255.0, 1), "is_single": false, "delay": false, "attack": preload("res://players/magic/shield/shield.scn"), "charge": preload("res://players/magic/shield/charge.scn")}, 
					{"id":"magicmine", "auracolor": Color(1, 129/255.0, 0), "weaponcolor1": Color(1, 1, 0), "weaponcolor2": Color(78/255.0, 0 , 1), "is_single": true, "delay": false, "attack": preload("res://players/magic/magicmine/mine.scn")}, 
					{"id":"void", "auracolor": Color(110/255.0, 110/255.0, 122/255.0), "weaponcolor1": Color(0, 0, 0), "weaponcolor2": Color(1, 1, 1), "is_single": false, "delay": true, "attack": preload("res://players/magic/void/void.scn")}]
var selected_spell
var request_spell_change = 0
var spell_icons
var is_charging = false
var is_magic = false
var charge_counter = 0
const MAX_CHARGE = 100
var charge_obj
var magic_delay = false #prevent spamming on some attacks
var shield
var shield_delay = 0
var shield_current_delay = 0
var shield_alpha = 0
var request_single_spell = false
var current_mines = []
var max_mines = 3
var void_direction = 1
var camera_offset

func min_array(array):
	if (array.size() == 1):
		return array[0]
	elif (array.size() > 1):
		var min_float = array[0]
		for i in range(1, array.size() - 1):
			min_float = min(array[i], min_float)
		return min_float
	else:
		return null

# add and remove magic spell and other special effect collisions
# to prevent interfering with regular collision detection
func remove_from_blacklist(item):
	var size = area2d_blacklist.size()
	for i in range(size):
		if (i < area2d_blacklist.size() && area2d_blacklist[i] == item):
			area2d_blacklist.remove(i)
			if (item.has_node("magic")):
				magic_delay = false

func add_to_blacklist(item):
	area2d_blacklist.append(item)

# slopes have the format slope#-#, where # denotes the 
# position (from the top) of the corner of the slope from left to right
func isSlope(name):
	return name.match("slope*-*")

func getSlopes(space_state):
	var relevantSlopeTile = space_state.intersect_ray(Vector2(get_global_pos().x, get_global_pos().y+sprite_offset.y), Vector2(get_global_pos().x, get_global_pos().y+sprite_offset.y+8), area2d_blacklist, 2147483647, 16)
	if (relevantSlopeTile.has("collider")):
		var collider = relevantSlopeTile["collider"]
		if (isSlope(collider.get_name())):
			return collider
	return null
	
func getClimbPlatform(space_state, direction):
	# true = check left side
	# false = check right side
	var platformY = get_global_pos().y - sprite_offset.y + 16
	var relevantTile = null
	if (direction):
		relevantTile = space_state.intersect_ray(Vector2(get_global_pos().x - sprite_offset.x, platformY), Vector2(get_global_pos().x - sprite_offset.x - 16, platformY), [self])
	else:
		relevantTile = space_state.intersect_ray(Vector2(get_global_pos().x + sprite_offset.x, platformY), Vector2(get_global_pos().x + sprite_offset.x + 16, platformY), [self])

	if (relevantTile.has("collider")):
		if(relevantTile["collider"].has_node("climbable")):
			return relevantTile["collider"]
	return null

func getLadderTile(space_state):
	var leftX = get_global_pos().x - sprite_offset.x
	var ladderTile = space_state.intersect_ray(Vector2(leftX, get_global_pos().y - sprite_offset.y), Vector2(leftX, get_global_pos().y + sprite_offset.y), area2d_blacklist, 2147483647, 16)
	if (ladderTile.has("collider")):
		var tileName = ladderTile["collider"].get_name()
		if (tileName == "ladder" || tileName == "ladder_top"):
			return ladderTile["collider"]

	var rightX = get_global_pos().x + sprite_offset.x
	ladderTile = space_state.intersect_ray(Vector2(rightX, get_global_pos().y - sprite_offset.y), Vector2(rightX, get_global_pos().y + sprite_offset.y), area2d_blacklist, 2147483647, 16)
	if (ladderTile.has("collider")):
		var tileName = ladderTile["collider"].get_name()
		if (tileName == "ladder" || tileName == "ladder_top"):
			return ladderTile["collider"]
	return null

func snapToLadder(ladder):
	var ladderX = ladder.get_global_pos().x - get_global_pos().x
	move(Vector2(ladderX, 0))

func getOneWayTile(space_state, desiredY):
	var leftX = get_global_pos().x - sprite_offset.x
	var oneWayTile = space_state.intersect_ray(Vector2(leftX, get_global_pos().y + sprite_offset.y), Vector2(leftX, get_global_pos().y + sprite_offset.y + desiredY), area2d_blacklist, 2147483647, 16)
	if (oneWayTile.has("collider")):
		if (oneWayTile["collider"].get_name() == "oneway"):
			return oneWayTile["collider"]
	return null

# we reused the damage rect to also check AB slopes from the side since they're not
# normal collisions and can be ignored.
func checkABSlope():
	var collisionTiles = damage_rect.get_overlapping_areas()
	for i in collisionTiles:
		if (i.get_name() == "slopea-b" && i.get_global_pos().y + TILE_SIZE/2 > int(get_pos().y - sprite_offset.y) && i.get_global_pos().y - TILE_SIZE/2 < int(get_pos().y + sprite_offset.y)):
			return true
	return false

func parseSlopeType(name):
	var values = name.split("slope")
	# slope#-#
	# extract #; first is left corner and last is right corner
	var slopes = values[1].split("-")
	if (slopes[0] == "a" && slopes[1] == "b"):
		return null
	return values[1].split_floats("-")

func clearMovingPlatform():
	movingPlatform = null
	movingPlatformPos = null

func closestXTile(direction, desiredX):
	# true = check left side
	# false = check right side
	if (is_colliding()):
		if (get_collision_pos().y > int(get_pos().y - sprite_offset.y) && get_collision_pos().y < int(get_pos().y + sprite_offset.y)):
			return 0
	return desiredX

func closestYTile(tileA, tileB):
	if (!tileA.has("position")):
		return tileB["position"].y
	elif (!tileB.has("position")):
		return tileA["position"].y
	else:
		return min(tileA["position"].y, tileB["position"].y)

func remove_weapon_collider():
	if (has_node(weapon_collider.get_name())):
		remove_child(weapon_collider)

func check_moving_platforms(normalTileCheck, relevantTileA, relevantTileB, space_state, oneWayTile):
	movingPlatform = null
	
	if (normalTileCheck):
		var movingPlatform_check = null
		if (relevantTileA.has("collider")):
			movingPlatform_check = relevantTileA["collider"]
		else:
			movingPlatform_check = relevantTileB["collider"]
		if(movingPlatform_check.get_name() == "blockR" || movingPlatform_check.get_name() == "blockL"):
			if (movingPlatform_check.get_global_pos().y - TILE_SIZE/2 >= int(get_pos().y + sprite_offset.y)):
				movingPlatform = movingPlatform_check
			else:
				clearMovingPlatform()
		else:
			clearMovingPlatform()

	# clear moving platforms if landing on one way platform tiles
	var onOneWayTile = false
	if (oneWayTile != null):
		onOneWayTile = oneWayTile.get_global_pos().y - TILE_SIZE/2 >= get_pos().y + sprite_offset.y
		clearMovingPlatform()

	if (climb_platform != null):
		if (climb_platform.get_name() == "blockR" || climb_platform.get_name() == "blockL"):
			movingPlatform = climb_platform
		else:
			clearMovingPlatform()

	if (movingPlatform != null):
		var newPos = Vector2(movingPlatform.get_global_pos().x, movingPlatform.get_global_pos().y)
		if (movingPlatformPos == null):
			movingPlatformPos = movingPlatform.get_parent()["previousPos_" + movingPlatform.get_name()]
		var movingDeltaX = newPos.x - movingPlatformPos.x
		# only move with the platform if landed on it
		# merely detecting it is there doesn't count
		if (int(get_pos().y + sprite_offset.y) >= newPos.y - TILE_SIZE/2 - 2 && !climbing_platform && !hanging):
			var platformDeltaX = 0
			if (get_global_pos().x + movingDeltaX > newPos.x + TILE_SIZE/2 || get_global_pos().x + movingDeltaX < newPos.x - TILE_SIZE/2):
				movingDeltaX = 0
		move(Vector2(movingDeltaX, newPos.y - movingPlatformPos.y))
		movingPlatformPos = newPos
	return onOneWayTile

func check_underwater(areaTiles):
	for i in areaTiles:
		if (i.get_name() == "water"):
			if (i.get_global_pos().y - TILE_SIZE/2 <= get_pos().y - sprite_offset.y):
				if (!underwater):
					get_node("sound").set_volume_db(get_node("sound").play("splash_down"), (fall_height/defaultfallheight*current_gravity - 1)*10)
				underwater = true
				current_gravity = WATER
			elif (i.get_global_pos().y + TILE_SIZE/2 >= get_pos().y + sprite_offset.y):
				if (underwater):
					get_node("sound").set_volume_db(get_node("sound").play("splash_up"), 0)
				underwater = false
				current_gravity = DEFAULT_GRAVITY

func check_damage(damageTiles):
	var is_hurt_check = false
	
	var dx = 0
	var dy = 0

	if (!invulnerable && shield == null):
		for i in damageTiles:
			print(i.get_name())
			if (i.get_name() == "damagable"):
				is_hurt_check = true
				dx += get_global_pos().x - i.get_global_pos().x
				dy += get_global_pos().y - i.get_global_pos().y
		
		# calculate throwback based on sum total positions of damagables
		if (dx != 0):
			dx = dx/abs(dx) * DAMAGE_THROWBACK
			damageDelta.x = int(dx)
		if (dy != 0):
			dy = dy/abs(dy) * VERTICAL_DAMAGE_THROWBACK
			damageDelta.y = int(dy)

	# check if there are still damagable tiles
	if (is_hurt_check):
		is_hurt = true
		invulnerable = true
		climbing_platform = false
	# proceed with hurt cycle
	else:
		if (is_hurt && damageDelta.x == 0 && damageDelta.y == 0):
			is_hurt = false
		if (damageDelta.x != 0):
			damageDelta.x = (abs(damageDelta.x) - 1) * damageDelta.x/abs(damageDelta.x)
		if (damageDelta.y != 0):
			damageDelta.y = (abs(damageDelta.y) - 1) * damageDelta.y/abs(damageDelta.y)

func check_ladder_horizontal(space_state):
	var ladderTile = getLadderTile(space_state)
		
	if (ladderTile != null && ladderTile.get_name() == "ladder_top"):
		ladder_top = ladderTile
	else:
		ladder_top = null
	
	if (on_ladder):
		ladderTile = getLadderTile(space_state)
		if (ladderTile == null):
			on_ladder = false

func step_horizontal(space_state):
	position.y = 0
	var new_animation = current_animation
	var horizontal_motion = false
	var forwardY = get_pos().y + sprite_offset.y
	var onSlope = false
	var slopeX = 0
	var relevantSlopeTile = null
	if (!climbing_platform && !is_crouching && !is_attacking && !is_hurt && !is_charging && !is_magic):
		if (Input.is_action_pressed("ui_left")):
			position.x = -min(runspeed, closestXTile(true, runspeed))
			# can't tell right now if we are on a slope tile and can ignore
			# the a-b slope tile
			# so delay horizontal motion until slope check
			if (checkABSlope()):
				slopeX = position.x
				position.x = 0
			new_animation = "run"
			direction = -1
			horizontal_motion = true
		elif (Input.is_action_pressed("ui_right")):
			position.x = min(runspeed, closestXTile(false, runspeed))
			if (checkABSlope()):
				slopeX = position.x
				position.x = 0
			new_animation = "run"
			direction = 1
			horizontal_motion = true
		else:
			position.x = 0
			new_animation = "idle"
		
		# disengage hanging on ledge if opposite button is pressed
		if (hanging && climb_platform != null):
				if ((direction < 0 && climb_platform.get_global_pos().x > get_global_pos().x) || (direction > 0 && climb_platform.get_global_pos().x < get_global_pos().x)):
					hanging = false
					move(Vector2(0, climb_platform.get_global_pos().y + TILE_SIZE/2 - get_pos().y + sprite_offset.y))
					climb_platform = null

		position.x = position.x * current_gravity

		move(position)
		
		position.x = 0
		
		# check ladder after horizontal movement
		check_ladder_horizontal(space_state)
		
	if (!on_ladder):
		# check slope tiles
		relevantSlopeTile = getSlopes(space_state)
		
		var onZeroSlope = false
		var currentSlopeTile = null
		var b = null
		forwardY = get_pos().y + sprite_offset.y
		if (relevantSlopeTile != null):
			b = parseSlopeType(relevantSlopeTile.get_name())
			if (b != null):
				if (b[0] == 0 || b[1] == 0):
					move(Vector2(slopeX, 0))
				onSlope = true
				b = parseSlopeType(relevantSlopeTile.get_name())
				# ignore bottom slopes if we're not close enough to them
				if ((b[0] == TILE_SIZE - 1 || b[1] == TILE_SIZE - 1) && (get_global_pos().x < relevantSlopeTile.get_global_pos().x - TILE_SIZE / 2 || get_global_pos().x > relevantSlopeTile.get_global_pos().x + TILE_SIZE / 2)):
					pass
				else:
					var t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE / 2)/TILE_SIZE
					var slopeY = (1 - t) * b[0] + t * b[1]
					
					var slopeAdjustedTileY = relevantSlopeTile.get_global_pos().y - TILE_SIZE / 2 + int(slopeY)
					
					# clamp to slope only if not jumping
					# unfortunately, the extra height from the default jump speed isn't enough to clear 
					# neighboring slopes. Playing with the values yields 5 as sufficient to do so
					if ((forwardY > slopeAdjustedTileY - (jumpspeed - 5)*current_gravity) || !jumpPressed):
						position.y = slopeAdjustedTileY - forwardY
						move(position)
	return {"animation": new_animation, "slope": onSlope, "slopeTile": relevantSlopeTile, "slopeX": slopeX, "motion": horizontal_motion}

func check_hanging_damage():
	if (hanging && climb_platform != null && is_hurt):
		hanging = false
		move(Vector2(0, climb_platform.get_global_pos().y + TILE_SIZE/2 - get_pos().y + sprite_offset.y))
		climb_platform = null

func check_climb_platform_horizontal(space_state):
	var climb_vertically = false
	if (!on_ladder && !is_hurt):
		var platform_check = null
		
		#if (!climbing_platform):
		platform_check = getClimbPlatform(space_state, direction == -1)
		
		# clamp to platform if should be hanging
		if (platform_check != null && !climbing_platform && climb_platform == null && !is_charging && !is_magic):
			hanging = true
			var d = platform_check.get_global_pos().x - direction * TILE_SIZE/2 - get_global_pos().x - direction * sprite_offset.x
			climb_platform = platform_check
			move(Vector2(d, 0))
			
		# stick with moving platform
		# more noticeable on faster horizontal platforms
		if (movingPlatform == climb_platform && climb_platform != null && hanging):
			var d = climb_platform.get_global_pos().x - direction * TILE_SIZE/2 - get_global_pos().x - direction * sprite_offset.x
			move(Vector2(d, 0))
		
		if (platform_check == null && climb_platform != null && !climbing_platform):
			climb_platform = null
			hanging = false
		
		# animate climbing platform
		# move a specific distance in an L shape to climb the platform every fixed function call
		# move up 4 tiles (the height of the character) and then left or right one tile
		# depending on how you choose to animate climbing, this may or may not
		# look very nice. If you have too few frames or don't adjust the vertical position, the
		# character can sometimes look like they're oscillating up and down on the platform
		# vertical motion is delayed until vertical motion checking
		if (climbing_platform && climb_platform != null):
			if (get_pos().y + sprite_offset.y <= climb_platform.get_global_pos().y - TILE_SIZE/2):
				move(Vector2(climbspeed * direction, 0))
				if ((direction == 1 && get_global_pos().x >= climb_platform.get_global_pos().x) || (direction == -1 && get_global_pos().x <= climb_platform.get_global_pos().x)):
					climb_platform = null
					climbing_platform = false
			# don't keep climbing if the platform isn't there anymore
			# but clamp to it horizontally if it is and we are moving up
			elif (get_pos().y - sprite_offset.y <= climb_platform.get_global_pos().y + TILE_SIZE/2) :
				var platformDeltaX = climb_platform.get_global_pos().x - direction * TILE_SIZE/2 - get_global_pos().x - sprite_offset.x * direction
				move(Vector2(platformDeltaX, 0))
				
				climb_vertically = true
			else:
				climbing_platform = false
		else: 
			climbing_platform = false
	return climb_vertically

func step_horizontal_damage_throwback():
	if (is_hurt):
		move(Vector2(damageDelta.x, 0))

func check_ladder_up(space_state):
	var ladderTile = getLadderTile(space_state)
	var ladderY = 0
	if (ladderTile != null):
		# only allow entering ladder from bottom
		if (!on_ladder && ladderTile.get_name() != "ladder_top"):
			on_ladder = true
			falling = false
			climbing_platform = false
			is_crouching = false
			snapToLadder(ladderTile)
			is_attacking = false
			remove_weapon_collider()
		elif (on_ladder):
			if (ladderTile.get_name() == "ladder_top"):
				ladder_top = ladderTile
			if (ladder_top != null):
				if (ladder_top.get_global_pos().y + TILE_SIZE/2 >= get_pos().y + sprite_offset.y):
					on_ladder = false
				else:
					var d = get_pos().y + sprite_offset.y - ladder_top.get_global_pos().y - TILE_SIZE/2
					ladderY = -min(LADDER_SPEED, d)
					snapToLadder(ladder_top)
			else:
				ladderY = -LADDER_SPEED
				snapToLadder(ladderTile)
	return ladderY

func check_ladder_down(space_state, normalTileCheck, onOneWayTile, relevantTileA, relevantTileB, animation_speed):
	var ladderTile = getLadderTile(space_state)
	var ladderY = 0
	if (ladderTile != null):
		# only allow entering ladder if not at the bottom
		if (!on_ladder && ((!normalTileCheck && !onOneWayTile) || ladder_top != null || ladderTile.get_name() == "ladder_top")):
			on_ladder = true
			falling = false
			climbing_platform = false
			is_crouching = false
			snapToLadder(ladderTile)
			is_attacking = false
			remove_weapon_collider()
		elif (on_ladder):
			if (normalTileCheck):
				var closestNormalTileY = closestYTile(relevantTileA, relevantTileB)
				var deltaY = closestNormalTileY - get_pos().y - sprite_offset.y
				if (int(deltaY) > 0):
					snapToLadder(ladderTile)
					ladderY = min(int(deltaY), LADDER_SPEED)
					animation_speed = -1
				else:
					accel = 0
					on_ladder = false
			else:
				snapToLadder(ladderTile)
				ladderY = LADDER_SPEED
				animation_speed = -1
	else:
		falling = true
		on_ladder = false
		# make sure we are really falling
		accel = max(1, accel)
	return {"ladderY": ladderY, "animationSpeed": animation_speed}

func check_ladder_top(normalTileCheck, closestTileY, desiredY):
	if (ladder_top != null && !normalTileCheck):
		var forwardY = get_pos().y + sprite_offset.y
		if (ladder_top.get_global_pos().y + TILE_SIZE/2 <= int(forwardY) && abs(accel) <= 1):
			# in theory, we'd like this to work as is, but without the extra - 2,
			# we run into collisions with neighboring ladder blocks
			# same reason we can't pass between static body tileset tiles with gaps
			# one tile wide
			move(Vector2(0, int(ladder_top.get_global_pos().y + TILE_SIZE/2 - forwardY - 2)))
			forwardY = get_pos().y + sprite_offset.y
			falling = false
		closestTileY = min(ladder_top.get_global_pos().y + TILE_SIZE/2 - forwardY, desiredY)
		closestTileY = int(closestTileY)

func check_jump():
	if (Input.is_action_pressed("ui_jump")):
		if (on_ladder && ladder_top == null):
			on_ladder = false
			falling = true
			jumpPressed = true
		elif (!on_ladder && (!falling || underwater) && !climbing_platform && !is_attacking):
			accel = -jumpspeed * current_gravity
			falling = true
			jumpPressed = true

#check conditions for absorbing blood
func check_blood(areaTiles):
	
	consumable = null

	for i in areaTiles:
		if (i.get_name() == "consumable"):
			consumable = i.get_parent()
	
	if (consumable != null && blood_requested && consumable.get("current_consume_value") > 0):
		blood_requested = false
		consumable.bleed()

func step_vertical(space_state, relevantTileA, relevantTileB, normalTileCheck, onOneWayTile, animation_speed, onSlope, oneWayTile, relevantSlopeTile):
	jumpPressed = false
	
	var ladderY = 0
	
	var forwardY = get_global_pos().y + sprite_offset.y
	crouch_requested = false
	
	if (!is_hurt && !is_charging && !is_magic):
		if (Input.is_action_pressed("ui_up")):
			ladderY = check_ladder_up(space_state)
			
			if (!on_ladder):
				if (hanging):
					hanging = false
					climbing_platform = true
	
		check_jump()
	
		if (Input.is_action_pressed("ui_down")):
			crouch_requested = true
			var ladderCheck = check_ladder_down(space_state, normalTileCheck, onOneWayTile, relevantTileA, relevantTileB, animation_speed)
			ladderY = ladderCheck["ladderY"]
			animation_speed = ladderCheck["animationSpeed"]

			if (hanging && !on_ladder):
				hanging = false
	
	# don't register throwback if jumping
	if (is_hurt && !(falling && accel < 0)):
		accel += damageDelta.y
	
	var desiredY = 0
	
	var abSlope = null
	# don't bother checking regular tiles below character if on ladder
	if (!on_ladder):
		desiredY = accel
		
		if (falling):
			desiredY += 1 * current_gravity * current_gravity
		else:
			desiredY = 1
		
		var s = 1
		
		if (desiredY < 0):
			s = -1
		
		relevantSlopeTile = getSlopes(space_state)
		
		var closestTileY = desiredY

		# check regular static blocks
		if (normalTileCheck):
			closestTileY = closestYTile(relevantTileA, relevantTileB)
	
			closestTileY -= get_pos().y+sprite_offset.y
			closestTileY = int(closestTileY)
	
			# prevent sticking to ceiling
			if (closestTileY == 0):
				if s == -1:
					closestTileY = jumpspeed - 1
				# landed on a platform; not falling anymore
				if s == 1:
					falling = false
		
			# ensure we are falling if not mediated by jumping
			if (abs(desiredY) < abs(closestTileY)):
				falling = true
		forwardY = get_pos().y + sprite_offset.y
		
		# check slopea-b tiles from above
		var collisionTiles = damage_rect.get_overlapping_areas()
		for i in collisionTiles:
			if (i.get_name() == "slopea-b" && i.get_global_pos().y + TILE_SIZE/2 >= int(get_pos().y - sprite_offset.y) && i.get_global_pos().y - TILE_SIZE/2 < int(get_pos().y - sprite_offset.y)):
				#closestTileY = max(i.get_global_pos().y + TILE_SIZE/2 - get_pos().y + sprite_offset.y, desiredY)
				move(Vector2(0, i.get_global_pos().y + TILE_SIZE/2 - get_pos().y + sprite_offset.y))

		# check slope tiles
		if (relevantSlopeTile != null):
			var closestSlopeTile = null
			var t
			var b
			var slopeY = 0
			var closest_level = null
			# find relevant distances to slope tiles
			b = parseSlopeType(relevantSlopeTile.get_name())
			if (b != null):
				t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE/2) / TILE_SIZE
				slopeY = (1 - t) * b[0] + t * b[1]
				if (forwardY <= relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + int(slopeY)):
					closest_level = relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 - forwardY
					b = parseSlopeType(relevantSlopeTile.get_name())
					t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE/2)/TILE_SIZE
					slopeY = (1 - t) * b[0] + t * b[1]
					
					# check that we are really standing on a slope tile
					if (relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY - forwardY < jumpspeed - 1):
						onSlope = true
						falling = false
					
					# don't need to check slope on ceilings
					if (forwardY >= relevantSlopeTile.get_global_pos().y + TILE_SIZE/2):
						closestTileY = forwardY - relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 - TILE_SIZE
					elif (forwardY <= relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY):
						closestTileY = relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY - forwardY
						if (jumpPressed):
							closestTileY = desiredY

					closestTileY = int(closestTileY)
			else:
				# not standing on a slope. This is just a block whose collision
				# is ignorable when standing on a slope tile next to it.
				abSlope = relevantSlopeTile
				if (abSlope.get_global_pos().y - TILE_SIZE/2 <= forwardY):
					move(Vector2(0, abSlope.get_global_pos().y - TILE_SIZE/2 - forwardY - 1))
					forwardY = get_pos().y + sprite_offset.y
				closestTileY = min(abSlope.get_global_pos().y - TILE_SIZE/2 - forwardY - 1, desiredY)
				closestTileY = int(closestTileY)
				falling = false
		
		# handle one way tiles
		if (onOneWayTile):
			if (oneWayTile.get_global_pos().y - TILE_SIZE/2 <= int(forwardY) + 1):
				move(Vector2(0, oneWayTile.get_global_pos().y - TILE_SIZE/2 - int(forwardY) - 1))
				forwardY = get_pos().y + sprite_offset.y
				falling = false
			closestTileY = min(oneWayTile.get_global_pos().y - TILE_SIZE/2 - int(forwardY) - 1, desiredY)
			closestTileY = int(closestTileY)
		
		# handle standing on a ladder_top tile
		check_ladder_top(normalTileCheck, closestTileY, desiredY)
		
		accel = min(min(abs(desiredY), abs(closestTileY)), SPEED_LIMIT * current_gravity) * s
	return {"desiredY": desiredY, "slope": onSlope, "slopeTile": relevantSlopeTile, "abSlope": abSlope, "animationSpeed": animation_speed, "ladderY": ladderY}

func check_falling(normalTileCheck, relevantSlopeTile, onSlope, abSlope, ladder_top, oneWayTile):
	if (!normalTileCheck && ((relevantSlopeTile == null || !onSlope) && abSlope == null) && ladder_top == null && oneWayTile == null):
			falling = true

func check_crouch(normalTileCheck, abSlope, onSlope, onOneWayTile):
	if (crouch_requested && !is_attacking && !falling && (normalTileCheck || onSlope || abSlope != null || onOneWayTile)):
		is_crouching = true
	elif (!crouch_requested && !is_attacking):
		is_crouching = false

func check_climb_platform_vertical(climb_vertically):
	# clamp to platform vertically to prevent falling while hanging with no input
	if (hanging && climb_platform != null):
		accel = climb_platform.get_global_pos().y - TILE_SIZE/2 - get_pos().y + sprite_offset.y

	# move character up from climbing ledge
	# see notes in horizontal motion about animation
	if (climb_vertically && climbing_platform):
		#var d = climb_platform.get_global_pos().y - TILE_SIZE/2 - get_pos().y + sprite_offset.y
		accel = -climbspeed
		falling = false

func check_on_moving_platform(desiredY):
	if (desiredY > - jumpspeed + 1 && movingPlatform != null && !hanging && !climbing_platform && movingPlatform.get_global_pos().y - TILE_SIZE/2 >= get_pos().y + sprite_offset.y):
		falling = false

func check_attacking():
	# only allow attacks to hit objects once during a hit
	if (weapon_collided):
		remove_weapon_collider()
		weapon_collided = false

	# handle attacking
	if ((animation_player.get_current_animation().match("*attack") && animation_player.get_current_animation_length() == animation_player.get_current_animation_pos()) || climbing_platform || hanging || on_ladder):
		is_attacking = false
		remove_weapon_collider()
	elif (!is_attacking && attack_requested && !is_hurt):
		attack_requested = false
		if (!hanging && !climbing_platform):
			do_attack()

func do_attack():
	is_attacking = true
	var weapon_height = 0
	if (is_crouching):
		weapon_height = sprite_offset.y
	get_node("sound").set_volume_db(get_node("sound").play("attack"), -10)
	weapon_collider.set_pos(Vector2((weapon_offset.x + sprite_offset.x + 4) * direction, -sprite_offset.y + weapon_offset.y + weapon_height))
	add_child(weapon_collider)
	weapon_collided = false
	
func update_fusion():
	var current_spell = magic_spells[selected_spell]
	var auracolor = current_spell["auracolor"]
	var weaponcolor1 = current_spell["weaponcolor1"]
	var weaponcolor2 = current_spell["weaponcolor2"]
	
	update_attack_color("attack", auracolor, weaponcolor1, weaponcolor2)
	update_attack_color("aattack", auracolor, weaponcolor1, weaponcolor2)
	update_attack_color("dattack", auracolor, weaponcolor1, weaponcolor2)
	
func update_attack_color(key, auracolor, weaponcolor1, weaponcolor2):
	get_node("NormalSpriteGroup/"+key+"/aura").set_modulate(auracolor)
	get_node("NormalSpriteGroup/"+key+"/"+weapon_type).get_material().set_shader_param("modulate", weaponcolor1)
	get_node("NormalSpriteGroup/"+key+"/"+weapon_type).get_material().set_shader_param("aura_color", weaponcolor2)

func check_attack_animation(new_animation):
	if (is_attacking):
		var modifier = ""
		if (is_crouching):
			modifier = "d"
		if (falling):
			modifier = "a"
		new_animation = modifier + "attack"
	return new_animation

func check_animations(new_animation, animation_speed, horizontal_motion, ladderY):
	if (!on_ladder):
		if (falling):
			if (accel < 0):
				new_animation = "jump"
			else:
				new_animation = "fall"

		if (!falling && ((animation_player.get_current_animation() == "land" && animation_player.is_playing()) || current_animation == "fall")):
			if (!horizontal_motion):
				new_animation = "land"
			if (current_animation != "land"):
				get_node("sound").set_volume_db(get_node("sound").play("land"), (fall_height/defaultfallheight*current_gravity - 1)*10)
		
		if (!falling && animation_player.get_current_animation().match("*aattack")):
			attack_frame = animation_player.get_current_animation_pos()
		
		if (is_crouching):
			new_animation = "crouch"
		
		new_animation = check_attack_animation(new_animation)
		
		if (is_charging):
			new_animation = "charge"

		if (is_magic):
			if(current_animation != "magic" || (current_animation == "magic" && animation_player.get_current_animation_pos() != animation_player.get_current_animation_length())):
				new_animation = "magic"
			else:
				is_magic = false
				if (magic_spells[selected_spell]["id"] == "void" && charge_obj != null):
					charge_obj.queue_free()
					charge_obj = null
					magic_delay = false
		
		if (climbing_platform || hanging):
			new_animation = "climb"
			if (hanging):
				animation_speed = 0
		
		if (is_hurt):
			new_animation = "hurt"
			if (damageDelta.x != 0):
				direction = -damageDelta.x/abs(damageDelta.x)
		
		if (invulnerable):
			hurt_grace_cycle += 1
			var alpha = 0.5 + fmod(hurt_grace_cycle, 4)*0.1
			get_node("NormalSpriteGroup").set_opacity(alpha)
			if (hurt_grace_cycle > HURT_GRACE_PERIOD):
				hurt_grace_cycle = 0
				invulnerable = false
				get_node("NormalSpriteGroup").set_opacity(1)

	if (on_ladder):
		direction = 1
		position.y = ladderY
		new_animation = "ladder"
		if (ladderY == 0):
			animation_speed = 0

	get_node("NormalSpriteGroup/"+new_animation).set_scale(Vector2(direction, 1))
	return {"animationSpeed": animation_speed, "animation": new_animation}

func calculate_fall_height():
	if (falling):
		fall_height += max(0, position.y)
	else:
		fall_height = 0

func _fixed_process(delta):
	step_player(delta)

func step_player(delta):
	var space = get_world_2d().get_space()
	var space_state = Physics2DServer.space_get_direct_state(space)
	var animation_speed = 1

	# position at character's feet
	var forwardY = get_global_pos().y + sprite_offset.y
	var leftX = get_global_pos().x - sprite_offset.x
	var rightX = get_global_pos().x + sprite_offset.x
	
	# bottom left ray check
	var relevantTileA = space_state.intersect_ray(Vector2(leftX, forwardY-1), Vector2(leftX, forwardY+16), [self])
	# bottom right ray check
	var relevantTileB = space_state.intersect_ray(Vector2(rightX, forwardY-1), Vector2(rightX, forwardY+16), [self])

	# check regular blocks
	var normalTileCheck = !relevantTileA.empty() || !relevantTileB.empty()
	
	# check moving platforms before everything else
	var oneWayTile = getOneWayTile(space_state, max(accel, TILE_SIZE))
	var onOneWayTile = check_moving_platforms(normalTileCheck, relevantTileA, relevantTileB, space_state, oneWayTile)
	
	var areaTiles = damage_rect.get_overlapping_areas()
	print("area tiles")
	print(areaTiles)
	# check underwater
	check_underwater(areaTiles)

	# check taking damage
	check_damage(areaTiles)
	
	# step horizontal motion first
	var horizontal = step_horizontal(space_state)
	var new_animation = horizontal["animation"]
	var horizontal_motion = horizontal["motion"]
	var onSlope = horizontal["slope"]
	var slopeX = horizontal["slopeX"]
	var relevantSlopeTile = horizontal["slopeTile"]
	forwardY = get_global_pos().y + sprite_offset.y
	
	# disengage hanging if hurt
	check_hanging_damage()
	
	# check platform climbing after horizontal movement requested
	var climb_vertically = check_climb_platform_horizontal(space_state)

	step_horizontal_damage_throwback()
	
	# check vertical motion
	var vertical = step_vertical(space_state, relevantTileA, relevantTileB, normalTileCheck, onOneWayTile, animation_speed, onSlope, oneWayTile, relevantSlopeTile)

	relevantSlopeTile = vertical["slopeTile"]
	var onSlope = vertical["slope"]
	var abSlope = vertical["abSlope"]
	var desiredY = vertical["desiredY"]
	animation_speed = vertical["animationSpeed"]
	var ladderY = vertical["ladderY"]
	
	if (!on_ladder):
		# final falling status check for all kinds of collisions
		check_falling(normalTileCheck, relevantSlopeTile, onSlope, abSlope, ladder_top, oneWayTile)

		# handle crouching now that we know if we are standing on ground blocks
		check_crouch(normalTileCheck, abSlope, onSlope, onOneWayTile)
		
		check_climb_platform_vertical(climb_vertically)

		# don't fall while standing on moving platforms moving up
		check_on_moving_platform(desiredY)

		check_attacking()
	
		position.y = accel
		
		check_blood(areaTiles)
		
		check_magic()
		
	# check animations
	var animations = check_animations(new_animation, animation_speed, horizontal_motion, ladderY)
	animation_speed = animations["animationSpeed"]
	new_animation = animations["animation"]

	calculate_fall_height()
	
	move(position)
	play_animation(new_animation, animation_speed)

func check_magic():
	# switch magic
	# only allow switching magic when they are not in "use"
	# ie, attacking because its effects and color are based off 
	# of currently selected magic
	if (request_spell_change != 0):
		if (is_attacking || is_charging || is_magic):
			request_spell_change = 0
		else:
			var prev_spell = selected_spell
			selected_spell += request_spell_change
			if (selected_spell >= magic_spells.size()):
				selected_spell = 0
			if (selected_spell < 0):
				selected_spell = magic_spells.size() - 1
			request_spell_change = 0
			spell_icons.get_node(magic_spells[prev_spell]["id"]).hide()
			spell_icons.get_node(magic_spells[selected_spell]["id"]).show()
			
			update_fusion()
	# detect magic requested
	var magic_allowed = !is_hurt && !is_attacking && !is_crouching && !hanging && !is_charging && !is_magic && !magic_delay
	if (magic_allowed && Input.is_action_pressed("ui_magic")):
		if (!magic_spells[selected_spell]["is_single"]):
			request_single_spell = false
			is_charging = true
			charge_counter += 1
			if (magic_spells[selected_spell]["delay"]):
				magic_delay = true
			if (magic_spells[selected_spell]["id"] == "fire" || magic_spells[selected_spell]["id"] == "ice"):
				charge_obj = magic_spells[selected_spell]["attack"].instance()
				charge_obj.set_global_pos(get_global_pos())
				tilemap.add_child(charge_obj)
				charge_obj.change_direction(direction)
				charge_obj.set("camera", get_node("Camera2D"))
			if (magic_spells[selected_spell]["id"] == "thunder"):
				charge_obj = magic_spells[selected_spell]["charge"].instance()
				add_child(charge_obj)
			if (magic_spells[selected_spell]["id"] == "hex"):
				if (falling):
					is_charging = false
					charge_counter = 0
					magic_delay = false
				else:
					charge_obj = magic_spells[selected_spell]["attack"].instance()
					charge_obj.set_global_pos(Vector2(get_global_pos().x, get_global_pos().y + sprite_offset.y))
					charge_obj.set("player", self)
					tilemap.add_child(charge_obj)
			if (magic_spells[selected_spell]["id"] == "shield"):
				if (shield == null):
					charge_obj = magic_spells[selected_spell]["charge"].instance()
					charge_obj.set_pos(Vector2(0, sprite_offset.y))
					add_child(charge_obj)
				else:
					is_charging = false
					charge_counter = 0
			if (magic_spells[selected_spell]["id"] == "void"):
				charge_obj = magic_spells[selected_spell]["attack"].instance()
				charge_obj.set_global_pos(Vector2(get_global_pos().x + direction * TILE_SIZE * 2, get_global_pos().y))
				charge_obj.set_scale(Vector2(direction, 1))
				tilemap.add_child(charge_obj)
				void_direction = direction
			if (magic_spells[selected_spell]["id"] == "earth"):
				charge_obj = magic_spells[selected_spell]["charge"].instance()
				charge_obj.set_pos(Vector2(0, sprite_offset.y))
				add_child(charge_obj)
	# charge magic
	elif (is_charging):
		if (Input.is_action_pressed("ui_magic")):
			charge_counter = min(charge_counter + 1, MAX_CHARGE)
			if (magic_spells[selected_spell]["id"] == "fire" || magic_spells[selected_spell]["id"] == "ice"):
				charge_obj.set_global_pos(get_global_pos())
				var scale = (3 - 0.7)*charge_counter/MAX_CHARGE + 0.7
				charge_obj.change_scale(scale)
			if (magic_spells[selected_spell]["id"] == "thunder"):
				var scale = (3 - 0.7)*charge_counter/MAX_CHARGE + 0.7
				charge_obj.change_scale(scale)
			if (magic_spells[selected_spell]["id"] == "hex"):
				charge_obj.set_global_pos(Vector2(get_global_pos().x, get_global_pos().y + sprite_offset.y))
				var scale = charge_counter/float(MAX_CHARGE) + 1
				charge_obj.change_scale(scale)
			if (magic_spells[selected_spell]["id"] == "shield"):
				var scale = charge_counter/float(MAX_CHARGE) + 1
				charge_obj.set_scale(Vector2(scale, scale))
			if (magic_spells[selected_spell]["id"] == "void"):
				# oscillate portal position
				var offset = charge_obj.get_global_pos().x + void_direction * 5
				var horizontal_bound = get_global_pos().x - direction * get_node("Camera2D").get_offset().x
				if ((offset >= horizontal_bound && direction > 0) || (offset <= horizontal_bound && direction < 0) ||
				(offset <= get_global_pos().x + direction * 2 * TILE_SIZE && direction > 0) || (offset >= get_global_pos().x + direction * 2 * TILE_SIZE && direction < 0)):
					void_direction = void_direction * -1
					offset = charge_obj.get_global_pos().x + void_direction * 10
				charge_obj.set_global_pos(Vector2(offset, get_global_pos().y))
			if (magic_spells[selected_spell]["id"] == "earth"):
				var velocity = 160.0 * charge_counter / MAX_CHARGE + 40
				var size = float(charge_counter) / MAX_CHARGE + 1
				charge_obj.get_node("rocks").set_param(Particles2D.PARAM_LINEAR_VELOCITY, velocity)
				charge_obj.get_node("rocks").set_param(Particles2D.PARAM_FINAL_SIZE, size)
		else:
			var scale = (3 - 0.7)*charge_counter/MAX_CHARGE + 0.7
			var charge_power = charge_counter
			charge_counter = 0
			is_charging = false
			is_magic = true
			if (magic_spells[selected_spell]["id"] == "fire" || magic_spells[selected_spell]["id"] == "ice"):
				charge_obj.release()
				charge_obj = null
			if (magic_spells[selected_spell]["id"] == "thunder"):
				charge_obj.queue_free()
				charge_obj = null
				var thunder = magic_spells[selected_spell]["attack"].instance()
				thunder.set_width(scale)
				thunder.set_global_pos(Vector2(get_global_pos().x, get_global_pos().y + get_node("Camera2D").get_offset().y))
				thunder.set("player", self)
				tilemap.add_child(thunder)
				# don't check own magic collisions for special platforms
				area2d_blacklist.append(thunder.get_node("collision/Area2D"))
			if (magic_spells[selected_spell]["id"] == "hex"):
				charge_obj.release()
				area2d_blacklist.append(charge_obj.get_node("beam/collision"))
				charge_obj = null
			if (magic_spells[selected_spell]["id"] == "shield"):
				if (has_node(charge_obj.get_name())):
					remove_child(charge_obj)
				charge_obj = null
				shield = magic_spells[selected_spell]["attack"].instance()
				shield_delay = 300 * ((scale - 0.7)/(3 - 0.7) + 1)
				shield_current_delay = 0
				var shieldbody = shield.get_node("shield")
				var shieldcolor = shieldbody.get_modulate()
				shield_alpha = 0.5 * (scale - 1)/2.0
				shieldbody.set_modulate(Color(shieldcolor.r, shieldcolor.g, shieldcolor.b, shield_alpha))
				add_child(shield)
				shield.get_node("AnimationPlayer").play("rotate")
			if (magic_spells[selected_spell]["id"] == "void"):
				if (charge_obj.get("is_valid")):
					set_global_pos(charge_obj.get_global_pos())
					charge_obj.set("is_set", true)
				else:
					# cancel the spell if the portal is not over a
					# valid position (ie, no collidable tiles, enemies, etc)
					charge_obj.queue_free()
					charge_obj = null
					magic_delay = false
			if (magic_spells[selected_spell]["id"] == "earth"):
				if (has_node(charge_obj.get_name())):
					remove_child(charge_obj)
				var earthquake_obj = magic_spells[selected_spell]["attack"].instance()
				earthquake_obj.set("player", self)
				earthquake_obj.set("camera", get_node("Camera2D"))
				earthquake_obj.set("tilemap", tilemap)
				earthquake_obj.set("earthquake_power", charge_power)
				earthquake_obj.set_global_pos(get_global_pos())
				area2d_blacklist.append(earthquake_obj.get_node("screen"))
				tilemap.add_child(earthquake_obj)
				
	# step shield state if it is active
	if (shield != null):
		shield_current_delay += 1
		var alpha = (1 - shield_current_delay/shield_delay) * shield_alpha
		var shieldbody = shield.get_node("shield")
		var shieldcolor = shieldbody.get_modulate()
		shieldbody.set_modulate(Color(shieldcolor.r, shieldcolor.g, shieldcolor.b, alpha))
		if (shield_current_delay >= shield_delay):
			if (has_node(shield.get_name())):
				remove_child(shield)
			shield = null
	# handle single shot spells
	if (magic_allowed && request_single_spell && magic_spells[selected_spell]["is_single"]):
		request_single_spell = false
		if (magic_spells[selected_spell]["id"] == "magicmine"):
			if (current_mines.size() < max_mines):
				var mine = magic_spells[selected_spell]["attack"].instance()
				current_mines.append(mine)
				mine.set("player", self)
				area2d_blacklist.append(mine.get_node("sensor"))
				mine.set_global_pos(Vector2(get_global_pos().x + TILE_SIZE * 2 * direction, get_global_pos().y))
				tilemap.add_child(mine)
				is_magic = true

func clear_mine(mine):
	var size = current_mines.size()
	for i in range(size):
		if (i < current_mines.size() && current_mines[i] == mine):
			current_mines.remove(i)

func _input(event):
	if (event.is_action_pressed("ui_attack") && event.is_pressed() && !event.is_echo()):
		attack_requested = true
	if (event.is_action_pressed("ui_blood") && event.is_pressed() && !event.is_echo()):
		blood_requested = true
	if (event.is_action_pressed("ui_spell_next") && event.is_pressed() && !event.is_echo() && !is_attacking):
		request_spell_change = 1
	if (event.is_action_pressed("ui_spell_prev") && event.is_pressed() && !event.is_echo() && !is_attacking):
		request_spell_change = -1
	if (event.is_action_pressed("ui_magic") && event.is_pressed() && !event.is_echo()):
		request_single_spell = true

func _ready():
	collision = get_node("CollisionShape2D")
	sprite_offset = collision.get_shape().get_extents()
	animation_player = get_node("AnimationPlayer")
	climbspeed = animation_player.get_animation("climb").get_length() * 6
	damage_rect = get_node("damage")
	spell_icons = get_tree().get_root().get_node("world/gui/CanvasLayer/hud/SpellIcons")
	
	weapon_collider = weapon.instance()
	weapon_offset = weapon_collider.get_node("weapon").get_shape().get_extents()

	weapon_collider.connect("area_enter", self, "_on_weapon_collision")
	
	area2d_blacklist = [self, damage_rect, weapon_collider]
	
	get_node("sound").set_polyphony(10)
	
	set_process_input(true)
	set_fixed_process(true)
	camera_offset = get_node("Camera2D").get_offset()

# notify when weapon collides with stuff
func _on_weapon_collision(area):
	var collisions = weapon_collider.get_overlapping_areas()
	for i in collisions:
		if (i.get_name() != "damage" && i != weapon_collider && i.get_name() != "oneway" && !i.get_name().match("slope*") && i.get_name() != "ladder"):
			weapon_collided = true
	if(area.get_name() != "damage" && area != weapon_collider && area.get_name() != "oneway" && !area.get_name().match("slope*") && area.get_name() != "ladder"):
		weapon_collided = true

func load_tilemap(var tilemap_node):
	tilemap = tilemap_node.get_node("tilemap")

func play_animation(animation, speed):
	animation_player.set_speed(speed)
	if (current_animation != animation):
		animation_player.play(animation)
		if (animation == "crouch" && current_animation == "dattack"):
			animation_player.seek(animation_player.get_current_animation_length())
		if (animation.match("*attack") && !falling && attack_frame > 0):
			animation_player.advance(attack_frame)
			attack_frame = 0
		current_animation = animation

func loop_jump_animation():
	animation_player.seek(0.1, true)
	
func loop_fall_animation():
	animation_player.seek(0.2, true)

func loop_charge_animation():
	animation_player.seek(0.1, true)