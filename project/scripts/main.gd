extends Node2D

const SpeechService = preload("res://scripts/speech_service.gd")
const LabyrinthGenerator = preload("res://scripts/labyrinth_generator.gd")
const DogController = preload("res://scripts/dog_controller.gd")
const TherapyDatabase = preload("res://scripts/data/database.gd")
const TherapyModels = preload("res://scripts/data/models.gd")
const SessionLogger = preload("res://scripts/session_logger.gd")

const DEFAULT_WORDS := [
    {"word_id": "mama", "text": "mama", "phonemes": ["m", "a"], "difficulty": 1, "repetitions": 2},
    {"word_id": "lama", "text": "lama", "phonemes": ["l", "a", "m", "a"], "difficulty": 2, "repetitions": 1},
    {"word_id": "rama", "text": "rama", "phonemes": ["r", "a", "m", "a"], "difficulty": 2, "repetitions": 2},
]

@onready var tile_map: TileMap = $Labyrinth/TileMap
@onready var dog: DogController = $Dog
@onready var prompt_label: Label = $PromptLabel
@onready var status_label: Label = $StatusLabel
@onready var scenario_button: Button = $UI/ScenarioButton
@onready var scenario_editor: ScenarioEditor = $UI/ScenarioEditor

var speech_service: SpeechService = SpeechService.new()
var generator: LabyrinthGenerator = LabyrinthGenerator.new()
var database: TherapyDatabase = TherapyDatabase.new()
var session_logger: SessionLogger = SessionLogger.new()

var active_scenario: TherapyModels.Scenario
var words_by_id: Dictionary = {}

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
    add_child(session_logger)
    scenario_button.pressed.connect(_toggle_scenario_editor)
    scenario_editor.scenario_saved.connect(_on_scenario_saved)

    _load_words_index()
    _load_initial_scenario()

func _load_words_index() -> void:
    words_by_id.clear()
    var words := database.load_words()
    if words.is_empty():
        for data in DEFAULT_WORDS:
            var word := TherapyModels.TherapyWord.new()
            word.id = data["word_id"]
            word.display_text = data["text"]
            word.phonemes = data["phonemes"]
            word.difficulty = data["difficulty"]
            database.save_word(word)
        words = database.load_words()
    for word in words:
        words_by_id[word.id] = word

func _load_initial_scenario() -> void:
    var scenarios := database.load_scenarios()
    if scenarios.is_empty():
        active_scenario = TherapyModels.Scenario.new("scenario_default", "Scenariusz domyślny")
        active_scenario.difficulty = 1
        var index := 0
        active_scenario.nodes = []
        for data in DEFAULT_WORDS:
            var node := TherapyModels.ScenarioNode.new("node_%d" % (index + 1), index, data["word_id"])
            active_scenario.nodes.append(node)
            index += 1
        database.save_scenario(active_scenario, OS.get_environment("USER"), "Scenariusz domyślny")
    else:
        active_scenario = scenarios[0]
        for scenario in scenarios:
            if scenario.updated_at > active_scenario.updated_at:
                active_scenario = scenario
    _build_labyrinth_for_scenario()
    session_logger.set_scenario(active_scenario.id)
    _update_editor_with_scenario()

func _build_labyrinth_for_scenario() -> void:
    labyrinth_data = generator.generate(Vector2i(6, 6), _tasks_from_scenario(active_scenario))
    path = labyrinth_data.get("path", [])
    checkpoints = labyrinth_data.get("checkpoints", [])
    _configure_tiles()
    _build_labyrinth_tiles(labyrinth_data.get("grid", []))
    _prepare_initial_state()

func _tasks_from_scenario(scenario: TherapyModels.Scenario) -> Array:
    var tasks: Array = []
    for node in scenario.nodes:
        var word := words_by_id.get(node.word_id)
        if word == null:
            continue
        var repetitions := _default_repetitions(node.word_id)
        if repetitions <= 0:
            repetitions = max(1, scenario.difficulty)
        tasks.append({
            "word_id": node.word_id,
            "text": word.display_text,
            "repetitions": repetitions,
        })
    if tasks.is_empty():
        for data in DEFAULT_WORDS:
            tasks.append({
                "word_id": data["word_id"],
                "text": data["text"],
                "repetitions": data["repetitions"],
            })
    return tasks

func _default_repetitions(word_id: String) -> int:
    for data in DEFAULT_WORDS:
        if data["word_id"] == word_id:
            return data.get("repetitions", 1)
    return 1

func _toggle_scenario_editor() -> void:
    scenario_editor.visible = not scenario_editor.visible
    if scenario_editor.visible:
        scenario_editor.set_scenario(_clone_scenario(active_scenario))

func _on_scenario_saved(data: Dictionary) -> void:
    active_scenario = _scenario_from_dict(data)
    session_logger.set_scenario(active_scenario.id)
    _load_words_index()
    _build_labyrinth_for_scenario()
    _update_editor_with_scenario()

func _update_editor_with_scenario() -> void:
    if scenario_editor.visible:
        scenario_editor.set_scenario(_clone_scenario(active_scenario))

func _scenario_from_dict(data: Dictionary) -> TherapyModels.Scenario:
    var scenario := TherapyModels.Scenario.new(data.get("id", ""), data.get("name", ""))
    scenario.difficulty = data.get("difficulty", 1)
    scenario.created_at = data.get("created_at", Time.get_unix_time_from_system())
    scenario.updated_at = data.get("updated_at", scenario.created_at)
    scenario.notes_after_session = data.get("notes_after_session", "")
    scenario.nodes = []
    for node_dict in data.get("nodes", []):
        scenario.nodes.append(TherapyModels.ScenarioNode.new(node_dict.get("id", ""), node_dict.get("order_index", 0), node_dict.get("word_id", "")))
    return scenario

func _clone_scenario(source: TherapyModels.Scenario) -> TherapyModels.Scenario:
    var clone := TherapyModels.Scenario.new(source.id, source.name)
    clone.difficulty = source.difficulty
    clone.created_at = source.created_at
    clone.updated_at = source.updated_at
    clone.notes_after_session = source.notes_after_session
    clone.nodes = []
    for node in source.nodes:
        clone.nodes.append(TherapyModels.ScenarioNode.new(node.id, node.order_index, node.word_id))
    return clone

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
        session_logger.log_attempt(active_task.get("word_id", ""), true, text)
        if active_task["remaining"] <= 0:
            status_label.text = "Świetnie! Zadanie '%s' ukończone." % active_task.get("word_id", "")
            await _complete_current_checkpoint()
        else:
            status_label.text = "Dobrze! Powtórz jeszcze %d razy." % active_task["remaining"]
            prompt_label.text = "Powiedz ponownie: %s (%d)" % [active_task.get("target_text", ""), active_task["remaining"]]
    else:
        session_logger.log_attempt(active_task.get("word_id", ""), false, text)
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
    var tasks: Array = []
    for data in DEFAULT_WORDS:
        tasks.append({
            "word_id": data["word_id"],
            "text": data["text"],
            "repetitions": data["repetitions"],
        })
    return tasks

func _cell_to_global(cell: Vector2i) -> Vector2:
    return tile_map.to_global(tile_map.map_to_local(cell))
