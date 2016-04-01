
extends Control

var action
var data
var sfxclass = preload("res://gui/menu/sfx.scn")
var sfx

func _ready():
	_on_choice_focus_exit()
	sfx = sfxclass.instance()
	add_child(sfx)

func _on_choice_focus_enter():
	get_node("icon").show()
	sfx.play("cursor")

func _on_choice_focus_exit():
	get_node("icon").hide()