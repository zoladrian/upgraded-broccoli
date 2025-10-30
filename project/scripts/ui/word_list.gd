extends ItemList

class_name WordDragList

var _words: Array[Dictionary] = []

func set_words(words: Array) -> void:
    _words.clear()
    clear()
    for word in words:
        var entry := {
            "id": word.id,
            "display_text": word.display_text,
            "phonemes": word.phonemes,
            "difficulty": word.difficulty,
        }
        _words.append(entry)
        add_item("%s (%s)" % [word.display_text, ", ".join(word.phonemes)])

func _ready() -> void:
    allow_reselect = true
    select_mode = ItemList.SELECT_SINGLE

func get_drag_data(at_position: Vector2) -> Variant:
    var selected := get_item_at_position(at_position)
    if selected == -1:
        selected = get_selected_items()
        if selected.is_empty():
            return null
        selected = selected[0]
    var data := _words[selected]
    set_drag_preview(_make_preview(data))
    return {
        "type": "word",
        "word_id": data["id"],
        "display_text": data["display_text"],
    }

func _make_preview(data: Dictionary) -> Control:
    var label := Label.new()
    label.text = data.get("display_text", "")
    label.add_theme_color_override("font_color", Color.WHITE)
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    label.add_theme_constant_override("font_outline_size", 2)
    return label
