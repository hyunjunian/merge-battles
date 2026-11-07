extends CharacterBody2D
## Example player: moves with WASD / arrow keys. Replace or delete freely.

@export var speed: float = 400.0


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
