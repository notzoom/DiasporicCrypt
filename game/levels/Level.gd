
extends Node

var title
var complete = false
var map = 0 # percentage of the level player has visited
var tags = {"red": false, "green": false, "blue": false, "purple": false}
var type # quest, boss, bonus or colosseum
var position = Vector2() # position on the world map
var new = true
var node # level the catacombs should connect to
var teleportto # coordinates in the level the player starts in when first entering the level
var description
var mapid # map layout to use
var reward = 0

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	pass


