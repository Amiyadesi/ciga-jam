extends TextureRect

@export var offset:float
@export var duration:float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var pos := position.y
	position.y = -825
	await get_tree().create_timer(1).timeout
	var tween1 = create_tween()
	tween1.tween_property(self,"position:y",pos,1).from(-825).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tween1.finished
	var tween2 = create_tween()
	tween2.set_loops(-1)
	tween2.tween_property(self,"position:y",position.y-offset,duration)
	tween2.tween_property(self,"position:y",position.y+offset,duration)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
