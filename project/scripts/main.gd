extends Node2D

const SpeechService = preload("res://scripts/speech_service.gd")
const LabyrinthGenerator = preload("res://scripts/labyrinth_generator.gd")
const DogController = preload("res://scripts/dog_controller.gd")
const SpeechPipeline = preload("res://scripts/speech_pipeline.gd")

@onready var tile_map: TileMap = $Labyrinth/TileMap
@onready var dog: DogController = $Dog
@onready var prompt_label: Label = $PromptLabel
@onready var status_label: Label = $StatusLabel
@onready var manual_accept_button: Button = $ManualControls/ApproveButton
@onready var manual_retry_button: Button = $ManualControls/RetryButton

var speech_service: SpeechService = SpeechService.new()
var generator: LabyrinthGenerator = LabyrinthGenerator.new()
var speech_pipeline: SpeechPipeline = SpeechPipeline.new()

var recognizing := false
var labyrinth_data: Dictionary
var path: Array[Vector2i] = []
var checkpoints: Array = []
var current_checkpoint_index := -1
var active_task: Dictionary = {}
var current_path_index := 0
var pending_checkpoint_index := -1
var pending_path_index := 0
var last_evaluation: Dictionary = {}
var last_transcription := ""

var _floor_source_id := -1
var _wall_source_id := -1

func _ready() -> void:
    speech_pipeline = SpeechPipeline.new()
    speech_service.events.connect(_on_speech_event)
    speech_service.initialize()
    dog.path_completed.connect(_on_dog_path_completed)
    manual_accept_button.pressed.connect(_on_manual_accept_pressed)
    manual_retry_button.pressed.connect(_on_manual_retry_pressed)

    labyrinth_data = generator.generate(Vector2i(6, 6), _default_tasks())
    path = labyrinth_data.get("path", [])
    checkpoints = labyrinth_data.get("checkpoints", [])
    _configure_tiles()
    _build_labyrinth_tiles(labyrinth_data.get("grid", []))
    _prepare_initial_state()
    _update_manual_controls(true)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") or event is InputEventScreenTouch and event.is_pressed():
        if recognizing:
            speech_service.stop_listening()
        else:
            speech_service.start_listening()

func _on_speech_event(event: Dictionary) -> void:
    match event.get("type"):
        "transcription":
            last_transcription = event.get("text", "")
            status_label.text = "Rozpoznano: %s" % last_transcription
            await _evaluate_transcription(last_transcription)
        "error":
            status_label.text = "Błąd: %s" % event.get("message", "unknown")
        "listening":
            recognizing = event.get("active", false)
            prompt_label.text = recognizing ? "Mów teraz..." : _current_prompt()
            if recognizing:
                _update_manual_controls(true)
        "tts_complete":
            recognizing = false

func _prepare_initial_state() -> void:
    if path.is_empty():
        return
    current_path_index = 0
    pending_path_index = 0
    dog.global_position = _cell_to_global(path[0])
    if checkpoints.is_empty():
        prompt_label.text = "Brak zadań"
        status_label.text = ""
        _update_manual_controls(true)
        return
    _reveal_path_segment(0, checkpoints[0]["path_index"])
    _activate_checkpoint(0)

func _activate_checkpoint(index: int) -> void:
    if index < 0 or index >= checkpoints.size():
        _finish_labyrinth()
        return
    current_checkpoint_index = index
    active_task = checkpoints[index].duplicate(true)
    checkpoints[index] = active_task
    prompt_label.text = "Powiedz: %s (%d powt.)" % [active_task.get("target_text", ""), active_task.get("remaining", 1)]
    status_label.text = "Naciśnij Enter lub dotknij, aby rozpocząć."
    last_evaluation.clear()
    _update_manual_controls(true)

func _evaluate_transcription(text: String) -> void:
    if active_task.is_empty():
        return
    var target_text := String(active_task.get("target_text", ""))
    var context := {
        "key_phonemes": active_task.get("key_phonemes", []),
        "allowed_substitutions": active_task.get("allowed_substitutions", {}),
        "min_text_ratio": active_task.get("min_text_ratio", 0.65),
        "min_phoneme_score": active_task.get("min_phoneme_score", 0.55),
    }
    last_evaluation = speech_pipeline.evaluate(text, target_text, context)
    if last_evaluation.get("accepted", false):
        await _apply_success(last_evaluation, false)
    else:
        await _apply_failure(last_evaluation, false)

func _apply_success(evaluation: Dictionary, manual_override := false) -> void:
    if active_task.is_empty():
        return
    last_evaluation = evaluation
    last_evaluation["accepted"] = true
    var summary := _format_evaluation_summary(evaluation)
    var remaining := max(0, int(active_task.get("remaining", 1)) - 1)
    var word_id := active_task.get("word_id", "")
    var target_text := active_task.get("target_text", "")
    active_task["remaining"] = remaining
    checkpoints[current_checkpoint_index]["remaining"] = remaining

    if manual_override:
        status_label.text = "Zaliczono ręcznie (%s)." % summary
    else:
        status_label.text = "Świetnie! (%s)." % summary

    if remaining <= 0:
        status_label.text = "%s Zadanie '%s' ukończone." % [status_label.text, word_id]
        await _complete_current_checkpoint()
    else:
        prompt_label.text = "Powiedz ponownie: %s (%d)" % [target_text, remaining]
        status_label.text = "%s Pozostało %d powtórzeń." % [status_label.text, remaining]

    if manual_override:
        _update_manual_controls(true)
    else:
        _update_manual_controls(active_task.is_empty() or active_task.get("remaining", 0) <= 0)

func _apply_failure(evaluation: Dictionary, manual_override := false) -> void:
    last_evaluation = evaluation
    last_evaluation["accepted"] = false
    var summary := _format_evaluation_summary(evaluation)
    var notes := evaluation.get("notes", [])
    var note_text := ""
    if (typeof(notes) == TYPE_ARRAY or typeof(notes) == TYPE_PACKED_STRING_ARRAY) and not notes.is_empty():
        var text_notes: PackedStringArray = []
        for note in notes:
            text_notes.push_back(String(note))
        note_text = " | %s" % "; ".join(text_notes)
    var prefix := manual_override ? "Logopeda poprosił o poprawę" : "Spróbuj ponownie"
    status_label.text = "%s (%s)%s" % [prefix, summary, note_text]
    await dog.play_sit_feedback()
    prompt_label.text = _current_prompt()
    _update_manual_controls(false)

func _format_evaluation_summary(evaluation: Dictionary) -> String:
    var text_similarity := evaluation.get("text_similarity", 0.0)
    var phoneme_score := evaluation.get("phoneme_score", 0.0)
    var text_pct := int(round(text_similarity * 100.0))
    var phon_pct := int(round(phoneme_score * 100.0))
    return "tekst %d%% / fonemy %d%%" % [text_pct, phon_pct]

func _on_manual_accept_pressed() -> void:
    if active_task.is_empty():
        return
    if last_evaluation.is_empty():
        return
    if last_evaluation.get("accepted", false):
        return
    await _apply_success(last_evaluation, true)

func _on_manual_retry_pressed() -> void:
    if active_task.is_empty():
        return
    if last_evaluation.is_empty():
        status_label.text = "Logopeda poprosił o dodatkową próbę."
        prompt_label.text = _current_prompt()
        return
    if last_evaluation.get("accepted", false):
        var remaining := int(active_task.get("remaining", 0)) + 1
        active_task["remaining"] = remaining
        checkpoints[current_checkpoint_index]["remaining"] = remaining
        status_label.text = "Logopeda poprosił o dodatkową próbę (%d pozostało)." % remaining
        prompt_label.text = _current_prompt()
        last_evaluation.clear()
        _update_manual_controls(true)
    else:
        status_label.text = "Logopeda podtrzymał konieczność poprawy (%s)." % _format_evaluation_summary(last_evaluation)
        prompt_label.text = _current_prompt()

func _update_manual_controls(disabled: bool) -> void:
    if manual_accept_button:
        manual_accept_button.disabled = disabled or active_task.is_empty()
    if manual_retry_button:
        manual_retry_button.disabled = disabled or active_task.is_empty()

func _complete_current_checkpoint() -> void:
    active_task.clear()
    checkpoints[current_checkpoint_index]["completed"] = true
    var next_index := current_checkpoint_index + 1
    if next_index >= checkpoints.size():
        _reveal_path_segment(current_path_index, path.size() - 1)
        var exit_points := _path_points_between(current_path_index, path.size() - 1)
        if exit_points.is_empty():
            _finish_labyrinth()
        else:
            pending_checkpoint_index = -1
            pending_path_index = path.size() - 1
            dog.follow_path(exit_points)
        return

    var next_checkpoint := checkpoints[next_index]
    prompt_label.text = "Ścieżka do '%s' jest otwarta." % next_checkpoint.get("word_id", "")
    _reveal_path_segment(current_path_index, next_checkpoint["path_index"])
    var points := _path_points_between(current_path_index, next_checkpoint["path_index"])
    pending_checkpoint_index = next_index
    pending_path_index = next_checkpoint["path_index"]
    if points.is_empty():
        current_path_index = next_checkpoint["path_index"]
        _activate_checkpoint(pending_checkpoint_index)
    else:
        dog.follow_path(points)

func _on_dog_path_completed() -> void:
    current_path_index = pending_path_index
    if pending_checkpoint_index >= 0:
        _activate_checkpoint(pending_checkpoint_index)
        pending_checkpoint_index = -1
    elif current_path_index >= path.size() - 1:
        _finish_labyrinth()

func _finish_labyrinth() -> void:
    active_task.clear()
    prompt_label.text = "Labirynt ukończony!"
    status_label.text = "Gratulacje!"
    last_evaluation.clear()
    _update_manual_controls(true)

func _configure_tiles() -> void:
    var tile_set := TileSet.new()
    var floor_texture := _make_color_texture(Color(0.4, 0.7, 0.9))
    var wall_texture := _make_color_texture(Color(0.1, 0.1, 0.15))

    var floor_source := TileSetAtlasSource.new()
    floor_source.texture = floor_texture
    floor_source.create_tile(Vector2i.ZERO)
    tile_set.add_source(floor_source, 0)
    _floor_source_id = 0

    var wall_source := TileSetAtlasSource.new()
    wall_source.texture = wall_texture
    wall_source.create_tile(Vector2i.ZERO)
    tile_set.add_source(wall_source, 1)
    _wall_source_id = 1

    tile_set.tile_size = Vector2i(32, 32)
    tile_map.tile_set = tile_set
    tile_map.clear()

func _make_color_texture(color: Color) -> Texture2D:
    var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    image.fill(color)
    var texture := ImageTexture.create_from_image(image)
    return texture

func _build_labyrinth_tiles(grid: Array) -> void:
    for y in grid.size():
        var row = grid[y]
        for x in row.size():
            tile_map.set_cell(0, Vector2i(x, y), _wall_source_id, Vector2i.ZERO)

func _reveal_path_segment(from_index: int, to_index: int) -> void:
    var start_index := min(from_index, to_index)
    var end_index := max(from_index, to_index)
    for i in range(start_index, end_index + 1):
        var cell := path[i]
        tile_map.set_cell(0, cell, _floor_source_id, Vector2i.ZERO)

func _path_points_between(from_index: int, to_index: int) -> Array[Vector2]:
    var points: Array[Vector2] = []
    if to_index <= from_index:
        return points
    for i in range(from_index + 1, to_index + 1):
        points.append(_cell_to_global(path[i]))
    return points

func _current_prompt() -> String:
    if active_task.is_empty():
        return prompt_label.text
    return "Powiedz: %s (%d)" % [active_task.get("target_text", ""), active_task.get("remaining", 1)]

func _default_tasks() -> Array:
    return [
        {
            "word_id": "mama",
            "text": "mama",
            "repetitions": 2,
            "key_phonemes": ["m", "a"],
            "allowed_substitutions": {"m": ["b"], "a": ["e"]},
        },
        {
            "word_id": "lama",
            "text": "lama",
            "repetitions": 1,
            "key_phonemes": ["l", "m"],
            "allowed_substitutions": {"l": ["r"], "m": ["b"]},
        },
        {
            "word_id": "rama",
            "text": "rama",
            "repetitions": 2,
            "key_phonemes": ["r", "m"],
            "allowed_substitutions": {"r": ["l"], "m": ["b"]},
            "min_phoneme_score": 0.6,
        },
    ]

func _cell_to_global(cell: Vector2i) -> Vector2:
    return tile_map.to_global(tile_map.map_to_local(cell))
