extends Node2D

const SpeechService = preload("res://scripts/speech_service.gd")
const LabyrinthGenerator = preload("res://scripts/labyrinth_generator.gd")
const DogController = preload("res://scripts/dog_controller.gd")

@onready var tile_map: TileMap = $Labyrinth/TileMap
@onready var dog: DogController = $Dog
@onready var prompt_label: Label = $PromptLabel
@onready var status_label: Label = $StatusLabel

var speech_service: SpeechService = SpeechService.new()
var generator: LabyrinthGenerator = LabyrinthGenerator.new()

var recognizing := false
var labyrinth_data: Dictionary
var path: Array[Vector2i] = []
var checkpoints: Array = []
var current_checkpoint_index := -1
var active_task: Dictionary = {}
var current_path_index := 0
var pending_checkpoint_index := -1
var pending_path_index := 0

var _floor_source_id := -1
var _wall_source_id := -1

func _ready() -> void:
    speech_service.events.connect(_on_speech_event)
    speech_service.initialize()
    dog.path_completed.connect(_on_dog_path_completed)

    labyrinth_data = generator.generate(Vector2i(6, 6), _default_tasks())
    path = labyrinth_data.get("path", [])
    checkpoints = labyrinth_data.get("checkpoints", [])
    _configure_tiles()
    _build_labyrinth_tiles(labyrinth_data.get("grid", []))
    _prepare_initial_state()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") or event is InputEventScreenTouch and event.is_pressed():
        if recognizing:
            speech_service.stop_listening()
        else:
            speech_service.start_listening()

func _on_speech_event(event: Dictionary) -> void:
    match event.get("type"):
        "transcription":
            status_label.text = "Rozpoznano: %s" % event.get("text", "")
            await _evaluate_transcription(event.get("text", ""))
        "error":
            status_label.text = "Błąd: %s" % event.get("message", "unknown")
        "listening":
            recognizing = event.get("active", false)
            prompt_label.text = recognizing ? "Mów teraz..." : _current_prompt()
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

func _evaluate_transcription(text: String) -> void:
    if active_task.is_empty():
        return
    var normalized_input := text.strip_edges().to_lower()
    var normalized_target := String(active_task.get("target_text", "")).strip_edges().to_lower()
    if normalized_input == normalized_target and normalized_target != "":
        active_task["remaining"] = int(active_task.get("remaining", 1)) - 1
        checkpoints[current_checkpoint_index]["remaining"] = active_task["remaining"]
        if active_task["remaining"] <= 0:
            status_label.text = "Świetnie! Zadanie '%s' ukończone." % active_task.get("word_id", "")
            await _complete_current_checkpoint()
        else:
            status_label.text = "Dobrze! Powtórz jeszcze %d razy." % active_task["remaining"]
            prompt_label.text = "Powiedz ponownie: %s (%d)" % [active_task.get("target_text", ""), active_task["remaining"]]
    else:
        status_label.text = "Spróbuj ponownie. Pies siada."
        await dog.play_sit_feedback()
        prompt_label.text = _current_prompt()

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
        {"word_id": "mama", "text": "mama", "repetitions": 2},
        {"word_id": "lama", "text": "lama", "repetitions": 1},
        {"word_id": "rama", "text": "rama", "repetitions": 2},
    ]

func _cell_to_global(cell: Vector2i) -> Vector2:
    return tile_map.to_global(tile_map.map_to_local(cell))
