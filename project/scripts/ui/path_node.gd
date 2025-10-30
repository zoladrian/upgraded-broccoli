extends Panel

class_name LabyrinthPathNode

signal word_assigned(node_id: String, word_id: String)
signal cleared(node_id: String)

@export var node_id: String = ""
@onready var label: Label = $VBoxContainer/WordLabel

var assigned_word_id: String = ""
var _style_empty := StyleBoxFlat.new()
var _style_assigned := StyleBoxFlat.new()

func _ready() -> void:
    if node_id == "":
        node_id = str(get_instance_id())
    _style_empty.bg_color = Color(0.1, 0.1, 0.1, 0.7)
    _style_assigned.bg_color = Color(0.15, 0.4, 0.25, 0.9)
    add_theme_stylebox_override("panel", _style_empty)
    _update_visuals()

func can_drop_data(at_position: Vector2, data: Variant) -> bool:
    return typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "word"

func drop_data(at_position: Vector2, data: Variant) -> void:
    if not can_drop_data(at_position, data):
        return
    assigned_word_id = data.get("word_id", "")
    label.text = data.get("display_text", "")
    _update_visuals()
    emit_signal("word_assigned", node_id, assigned_word_id)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
        _clear_assignment()

func _clear_assignment() -> void:
    if assigned_word_id == "":
        return
    assigned_word_id = ""
    _update_visuals()
    emit_signal("cleared", node_id)

func _update_visuals() -> void:
    if assigned_word_id == "":
        label.text = "(puste)"
        add_theme_stylebox_override("panel", _style_empty)
    else:
        add_theme_stylebox_override("panel", _style_assigned)
