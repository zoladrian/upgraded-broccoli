extends Node

class_name SessionLogger

const TherapyModels = preload("res://scripts/data/models.gd")
const TherapyDatabase = preload("res://scripts/data/database.gd")

var database: TherapyDatabase
var current_scenario_id: String = ""
var attempt_counters: Dictionary = {}

signal entry_logged(entry: Dictionary)

func _ready() -> void:
    if database == null:
        database = TherapyDatabase.new()

func set_scenario(scenario_id: String) -> void:
    current_scenario_id = scenario_id
    attempt_counters.clear()

func log_attempt(word_id: String, success: bool, transcription: String, audio_path: String = "") -> void:
    if current_scenario_id == "":
        return
    var entry := TherapyModels.SessionLogEntry.new()
    entry.scenario_id = current_scenario_id
    entry.word_id = word_id
    entry.attempt_index = _next_attempt_index(word_id)
    entry.success = success
    entry.transcription = transcription
    entry.recorded_audio_path = audio_path
    entry.timestamp = Time.get_unix_time_from_system()
    if database:
        database.add_session_log(entry)
    emit_signal("entry_logged", entry.to_dict())

func _next_attempt_index(word_id: String) -> int:
    var count := attempt_counters.get(word_id, 0)
    count += 1
    attempt_counters[word_id] = count
    return count
