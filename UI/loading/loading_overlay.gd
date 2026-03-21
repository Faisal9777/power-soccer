extends CanvasLayer

@onready var spinner = $Blocker/Center/Panel/VBox/Row/Spinner
@onready var status  = $Blocker/Center/Panel/VBox/Row/Status

var _spinning := false


func _ready():
	hide()


func _process(delta):
	if _spinning:
		spinner.rotation += 4.0 * delta


func show_loading(text := "Loading..."):
	status.text = text
	show()
	_spinning = true


func hide_loading():
	_spinning = false
	hide()
