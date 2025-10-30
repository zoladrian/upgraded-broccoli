extends RefCounted

class_name TherapyDatabase

const DB_PATH := "user://therapy.db"

const TherapyModels = preload("res://scripts/data/models.gd")

var _sqlite: Object
var _connected := false

func _init(db_path: String = DB_PATH):
    if db_path != "":
        _connect(db_path)

func _connect(path: String) -> void:
    if ClassDB.class_exists("SQLite"):
        _sqlite = ClassDB.instantiate("SQLite")
        _sqlite.path = path
        var err := _sqlite.open_db()
        if err == OK:
            _connected = true
            _run_migrations()
        else:
            push_error("Unable to open SQLite database: %s" % err)
    else:
        push_warning("SQLite class is not available. Falling back to in-memory store.")
        _sqlite = null
        _connected = false
        _ensure_memory_store()

func _ensure_memory_store() -> void:
    if not ProjectSettings.has_setting("therapy/memory_db"):
        ProjectSettings.set_setting("therapy/memory_db", {
            "words": {},
            "scenarios": {},
            "scenario_versions": {},
            "session_logs": [],
        })

func _run_migrations() -> void:
    if not _connected:
        return
    _execute("CREATE TABLE IF NOT EXISTS words (id TEXT PRIMARY KEY, display_text TEXT, phonemes TEXT, difficulty INTEGER, media_paths TEXT)")
    _execute("CREATE TABLE IF NOT EXISTS scenarios (id TEXT PRIMARY KEY, name TEXT, difficulty INTEGER, created_at INTEGER, updated_at INTEGER, notes_after_session TEXT)")
    _execute("CREATE TABLE IF NOT EXISTS scenario_nodes (id TEXT PRIMARY KEY, scenario_id TEXT, order_index INTEGER, word_id TEXT, FOREIGN KEY(scenario_id) REFERENCES scenarios(id), FOREIGN KEY(word_id) REFERENCES words(id))")
    _execute("CREATE TABLE IF NOT EXISTS scenario_versions (scenario_id TEXT, version_number INTEGER, created_at INTEGER, author TEXT, notes TEXT, data TEXT, PRIMARY KEY(scenario_id, version_number))")
    _execute("CREATE TABLE IF NOT EXISTS session_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, scenario_id TEXT, word_id TEXT, attempt_index INTEGER, success INTEGER, transcription TEXT, recorded_audio_path TEXT, timestamp INTEGER)")

func _execute(query: String, params: Array = []) -> void:
    if _connected:
        _sqlite.query(query, params)

func save_word(word: TherapyWord) -> void:
    if _connected:
        _execute("REPLACE INTO words (id, display_text, phonemes, difficulty, media_paths) VALUES (?, ?, ?, ?, ?)", [word.id, word.display_text, JSON.stringify(word.phonemes), word.difficulty, JSON.stringify(word.media_paths)])
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        store["words"][word.id] = word.to_dict()
        ProjectSettings.set_setting("therapy/memory_db", store)

func load_words() -> Array[TherapyWord]:
    var results: Array[TherapyWord] = []
    if _connected:
        var query := _sqlite.select_rows("SELECT * FROM words ORDER BY display_text")
        for row in query:
            var word := TherapyModels.TherapyWord.new()
            word.id = row["id"]
            word.display_text = row["display_text"]
            word.phonemes = JSON.parse_string(row["phonemes"]) if row["phonemes"] else []
            word.difficulty = row["difficulty"]
            word.media_paths = JSON.parse_string(row["media_paths"]) if row["media_paths"] else []
            results.append(word)
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        for data in store.get("words", {}).values():
            results.append(TherapyWord.from_dict(data))
    return results

func save_scenario(scenario: TherapyModels.Scenario, author: String = "", notes: String = "") -> void:
    scenario.updated_at = Time.get_unix_time_from_system()
    if _connected:
        _execute("REPLACE INTO scenarios (id, name, difficulty, created_at, updated_at, notes_after_session) VALUES (?, ?, ?, ?, ?, ?)", [scenario.id, scenario.name, scenario.difficulty, scenario.created_at, scenario.updated_at, scenario.notes_after_session])
        _execute("DELETE FROM scenario_nodes WHERE scenario_id = ?", [scenario.id])
        for node in scenario.nodes:
            _execute("REPLACE INTO scenario_nodes (id, scenario_id, order_index, word_id) VALUES (?, ?, ?, ?)", [node.id, scenario.id, node.order_index, node.word_id])
        var version_data := scenario.to_dict()
        var next_version := _next_version_number(scenario.id)
        _execute("REPLACE INTO scenario_versions (scenario_id, version_number, created_at, author, notes, data) VALUES (?, ?, ?, ?, ?, ?)", [scenario.id, next_version, Time.get_unix_time_from_system(), author, notes, JSON.stringify(version_data)])
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        var scenarios: Dictionary = store.get("scenarios", {})
        scenarios[scenario.id] = scenario.to_dict()
        store["scenarios"] = scenarios
        var versions: Dictionary = store.get("scenario_versions", {})
        var existing_versions: Array = versions.get(scenario.id, [])
        existing_versions.append({
            "version_number": existing_versions.size() + 1,
            "created_at": Time.get_unix_time_from_system(),
            "author": author,
            "notes": notes,
            "data": scenario.to_dict(),
        })
        versions[scenario.id] = existing_versions
        store["scenario_versions"] = versions
        ProjectSettings.set_setting("therapy/memory_db", store)

func load_scenarios() -> Array[TherapyModels.Scenario]:
    var scenarios: Array[TherapyModels.Scenario] = []
    if _connected:
        var rows := _sqlite.select_rows("SELECT * FROM scenarios ORDER BY name")
        for row in rows:
            scenarios.append(_scenario_from_row(row))
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        for data in store.get("scenarios", {}).values():
            scenarios.append(_scenario_from_dict(data))
    return scenarios

func load_scenario_versions(scenario_id: String) -> Array[Dictionary]:
    if _connected:
        return _sqlite.select_rows("SELECT * FROM scenario_versions WHERE scenario_id = ? ORDER BY version_number DESC", [scenario_id])
    var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
    return store.get("scenario_versions", {}).get(scenario_id, [])

func add_session_log(entry: TherapyModels.SessionLogEntry) -> void:
    if _connected:
        _execute("INSERT INTO session_logs (scenario_id, word_id, attempt_index, success, transcription, recorded_audio_path, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)", [entry.scenario_id, entry.word_id, entry.attempt_index, entry.success ? 1 : 0, entry.transcription, entry.recorded_audio_path, entry.timestamp])
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        var logs: Array = store.get("session_logs", [])
        logs.append(entry.to_dict())
        store["session_logs"] = logs
        ProjectSettings.set_setting("therapy/memory_db", store)

func export_scenario_to_json(scenario: TherapyModels.Scenario, file_path: String) -> Error:
    var file := FileAccess.open(file_path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(scenario.to_dict(), "\t"))
        file.close()
        return OK
    return ERR_CANT_CREATE

func export_scenario_to_csv(scenario: TherapyModels.Scenario, file_path: String) -> Error:
    var file := FileAccess.open(file_path, FileAccess.WRITE)
    if not file:
        return ERR_CANT_CREATE
    file.store_line("order,word_id")
    for node in scenario.nodes:
        file.store_line("%d,%s" % [node.order_index, node.word_id])
    file.close()
    return OK

func _next_version_number(scenario_id: String) -> int:
    if _connected:
        var rows := _sqlite.select_rows("SELECT MAX(version_number) AS max_version FROM scenario_versions WHERE scenario_id = ?", [scenario_id])
        if not rows.is_empty():
            var max_version = rows[0]["max_version"]
            if typeof(max_version) == TYPE_INT:
                return max_version + 1
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        var versions: Array = store.get("scenario_versions", {}).get(scenario_id, [])
        return versions.size() + 1
    return 1

func _scenario_from_row(row: Dictionary) -> TherapyModels.Scenario:
    var scenario := TherapyModels.Scenario.new(row["id"], row["name"])
    scenario.difficulty = row["difficulty"]
    scenario.created_at = row["created_at"]
    scenario.updated_at = row["updated_at"]
    scenario.notes_after_session = row["notes_after_session"]
    scenario.nodes = _load_scenario_nodes(row["id"])
    return scenario

func _scenario_from_dict(data: Dictionary) -> TherapyModels.Scenario:
    var scenario := TherapyModels.Scenario.new(data.get("id", ""), data.get("name", ""))
    scenario.difficulty = data.get("difficulty", 1)
    scenario.created_at = data.get("created_at", Time.get_unix_time_from_system())
    scenario.updated_at = data.get("updated_at", scenario.created_at)
    scenario.notes_after_session = data.get("notes_after_session", "")
    scenario.nodes = []
    for node_dict in data.get("nodes", []):
        var node := TherapyModels.ScenarioNode.new(node_dict.get("id", ""), node_dict.get("order_index", 0), node_dict.get("word_id", ""))
        scenario.nodes.append(node)
    return scenario

func _load_scenario_nodes(scenario_id: String) -> Array[TherapyModels.ScenarioNode]:
    var nodes: Array[TherapyModels.ScenarioNode] = []
    if _connected:
        var rows := _sqlite.select_rows("SELECT * FROM scenario_nodes WHERE scenario_id = ? ORDER BY order_index", [scenario_id])
        for row in rows:
            nodes.append(TherapyModels.ScenarioNode.new(row["id"], row["order_index"], row["word_id"]))
    else:
        var store: Dictionary = ProjectSettings.get_setting("therapy/memory_db")
        var scenario_data: Dictionary = store.get("scenarios", {}).get(scenario_id, {})
        for node_dict in scenario_data.get("nodes", []):
            nodes.append(TherapyModels.ScenarioNode.new(node_dict.get("id", ""), node_dict.get("order_index", 0), node_dict.get("word_id", "")))
    return nodes
