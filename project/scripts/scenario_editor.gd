extends Control

class_name ScenarioEditor

signal scenario_saved(scenario_data: Dictionary)

const PathNodeScene = preload("res://scenes/PathNode.tscn")
const TherapyDatabase = preload("res://scripts/data/database.gd")
const TherapyModels = preload("res://scripts/data/models.gd")

@onready var word_list: WordDragList = $MarginContainer/VBoxContainer/Content/WordLibrary/WordsList
@onready var reload_words_button: Button = $MarginContainer/VBoxContainer/Content/WordLibrary/ReloadWords
@onready var id_input: LineEdit = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Form/IdInput
@onready var name_input: LineEdit = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Form/NameInput
@onready var difficulty_input: SpinBox = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Form/Difficulty
@onready var notes_input: TextEdit = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Form/Notes
@onready var save_button: Button = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Buttons/SaveScenario
@onready var export_json_button: Button = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Buttons/ExportJSON
@onready var export_csv_button: Button = $MarginContainer/VBoxContainer/Content/ScenarioDetails/Buttons/ExportCSV
@onready var versions_list: ItemList = $MarginContainer/VBoxContainer/Content/ScenarioDetails/VersionsPanel/VersionsList
@onready var add_node_button: Button = $MarginContainer/VBoxContainer/LabyrinthPanel/LabyrinthContent/Toolbar/AddNode
@onready var clear_nodes_button: Button = $MarginContainer/VBoxContainer/LabyrinthPanel/LabyrinthContent/Toolbar/ClearNodes
@onready var grid: GridContainer = $MarginContainer/VBoxContainer/LabyrinthPanel/LabyrinthContent/ScrollContainer/Grid
@onready var path_order_list: ItemList = $MarginContainer/VBoxContainer/LabyrinthPanel/LabyrinthContent/PathOrder
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusBar/StatusLabel

var database: TherapyDatabase
var active_scenario: TherapyModels.Scenario
var node_assignments: Dictionary = {}
var path_sequence: Array[String] = []
var _node_index := 0
var word_cache: Dictionary = {}

func _ready() -> void:
    database = TherapyDatabase.new()
    active_scenario = TherapyModels.Scenario.new()
    reload_words_button.pressed.connect(_load_words)
    save_button.pressed.connect(_save_scenario)
    export_json_button.pressed.connect(_export_json)
    export_csv_button.pressed.connect(_export_csv)
    add_node_button.pressed.connect(_add_path_node)
    clear_nodes_button.pressed.connect(_clear_assignments)
    _load_words()
    for i in range(6):
        _add_path_node()
    status_label.text = "Wczytano %d słów" % word_list.item_count

func set_scenario(scenario: TherapyModels.Scenario) -> void:
    active_scenario = scenario
    id_input.text = scenario.id
    name_input.text = scenario.name
    difficulty_input.value = scenario.difficulty
    notes_input.text = scenario.notes_after_session
    node_assignments.clear()
    path_sequence.clear()
    var children := grid.get_children()
    for child in children:
        child.queue_free()
    _node_index = 0
    var sorted_nodes := scenario.nodes.duplicate()
    sorted_nodes.sort_custom(self, "_sort_nodes")
    if sorted_nodes.is_empty():
        for i in range(6):
            _add_path_node()
        _refresh_path_order()
        _load_versions()
        status_label.text = "Przygotowano pusty scenariusz"
        return
    for node_data in sorted_nodes:
        var node := _add_path_node(node_data.id, "Węzeł %d" % (node_data.order_index + 1))
        node_assignments[node.node_id] = node_data.word_id
        path_sequence.append(node.node_id)
        node.assigned_word_id = node_data.word_id
        node.get_node("VBoxContainer/WordLabel").text = _word_display(node_data.word_id)
        node._update_visuals()
    _refresh_path_order()
    _load_versions()
    status_label.text = "Załadowano scenariusz '%s'" % scenario.name

func _load_words() -> void:
    var words := database.load_words()
    if words.is_empty():
        var demo_words := [
            {"id": "mama", "text": "mama", "phonemes": ["m", "a"], "difficulty": 1},
            {"id": "lama", "text": "lama", "phonemes": ["l", "a", "m", "a"], "difficulty": 2},
            {"id": "rama", "text": "rama", "phonemes": ["r", "a", "m", "a"], "difficulty": 2},
        ]
        for data in demo_words:
            var word := TherapyModels.TherapyWord.new()
            word.id = data["id"]
            word.display_text = data["text"]
            word.phonemes = data["phonemes"]
            word.difficulty = data["difficulty"]
            database.save_word(word)
        words = database.load_words()
    word_cache.clear()
    for word in words:
        word_cache[word.id] = word.display_text
    word_list.set_words(words)

func _add_path_node(existing_id: String = "", title: String = "") -> LabyrinthPathNode:
    var node := PathNodeScene.instantiate()
    if existing_id != "":
        node.node_id = existing_id
        var idx := int(existing_id.get_slice("_", 1)) if existing_id.find("_") != -1 else _node_index
        _node_index = max(_node_index, idx)
    else:
        _node_index += 1
        node.node_id = "node_%d" % _node_index
    var label_node: Label = node.get_node("VBoxContainer/TitleLabel")
    if title == "":
        title = "Węzeł %d" % (grid.get_child_count() + 1)
    label_node.text = title
    node.word_assigned.connect(_on_node_assigned)
    node.cleared.connect(_on_node_cleared)
    grid.add_child(node)
    return node

func _on_node_assigned(node_id: String, word_id: String) -> void:
    node_assignments[node_id] = word_id
    if not path_sequence.has(node_id):
        path_sequence.append(node_id)
    _refresh_path_order()
    status_label.text = "Przypisano słowo %s" % word_id

func _on_node_cleared(node_id: String) -> void:
    node_assignments.erase(node_id)
    path_sequence.erase(node_id)
    _refresh_path_order()
    status_label.text = "Wyczyszczono węzeł"

func _refresh_path_order() -> void:
    path_order_list.clear()
    for i in range(path_sequence.size()):
        var node_id := path_sequence[i]
        var word_id := node_assignments.get(node_id, "")
        path_order_list.add_item("%d. %s" % [i + 1, _word_display(word_id)])

func _word_display(word_id: String) -> String:
    if word_id == "":
        return "(puste)"
    return word_cache.get(word_id, word_id)

func _sort_nodes(a: TherapyModels.ScenarioNode, b: TherapyModels.ScenarioNode) -> bool:
    return a.order_index < b.order_index

func _collect_scenario() -> void:
    active_scenario.id = id_input.text.strip_edges()
    if active_scenario.id == "":
        active_scenario.id = "scenario_%d" % Time.get_unix_time_from_system()
    active_scenario.name = name_input.text.strip_edges()
    if active_scenario.name == "":
        active_scenario.name = "Nowy scenariusz"
    active_scenario.difficulty = int(difficulty_input.value)
    active_scenario.notes_after_session = notes_input.text
    active_scenario.nodes.clear()
    for i in range(path_sequence.size()):
        var node_id := path_sequence[i]
        var node := TherapyModels.ScenarioNode.new(node_id, i, node_assignments.get(node_id, ""))
        active_scenario.nodes.append(node)

func _save_scenario() -> void:
    _collect_scenario()
    if active_scenario.nodes.is_empty():
        status_label.text = "Dodaj co najmniej jeden węzeł z przypisanym słowem."
        return
    var author := OS.get_environment("USER")
    database.save_scenario(active_scenario, author, "")
    status_label.text = "Zapisano scenariusz '%s'" % active_scenario.name
    _load_versions()
    emit_signal("scenario_saved", active_scenario.to_dict())

func _load_versions() -> void:
    versions_list.clear()
    for version in database.load_scenario_versions(active_scenario.id):
        var title := "v%d - %s" % [version.get("version_number", 0), _format_timestamp(version.get("created_at", 0))]
        versions_list.add_item(title)

func _export_json() -> void:
    _collect_scenario()
    var dir_path := "user://exports"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
    var path := "%s/%s.json" % [dir_path, active_scenario.id]
    var err := database.export_scenario_to_json(active_scenario, path)
    status_label.text = err == OK ? "Wyeksportowano do JSON" : "Błąd eksportu JSON"

func _export_csv() -> void:
    _collect_scenario()
    var dir_path := "user://exports"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
    var path := "%s/%s.csv" % [dir_path, active_scenario.id]
    var err := database.export_scenario_to_csv(active_scenario, path)
    status_label.text = err == OK ? "Wyeksportowano do CSV" : "Błąd eksportu CSV"

func _clear_assignments() -> void:
    node_assignments.clear()
    path_sequence.clear()
    for child in grid.get_children():
        if child.has_method("_clear_assignment"):
            child._clear_assignment()
    path_order_list.clear()
    status_label.text = "Wyczyszczono przypisania"

func _format_timestamp(value: int) -> String:
    if value <= 0:
        return "--"
    var dt := Time.get_datetime_string_from_unix_time(value)
    return dt
