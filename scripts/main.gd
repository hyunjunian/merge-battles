extends Node2D
## Entry point of the game. Loaded as the main scene (see project.godot).


func _ready() -> void:
	print("Merge Battles started — Godot ", Engine.get_version_info().string)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
