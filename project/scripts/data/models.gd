extends Resource

class_name TherapyModels

class Word extends Resource:
    class_name TherapyWord
    @export var id: String
    @export var display_text: String
    @export var phonemes: Array[String] = []
    @export var difficulty: int = 1
    @export var media_paths: Array[String] = []

    func to_dict() -> Dictionary:
        return {
            "id": id,
            "display_text": display_text,
            "phonemes": phonemes,
            "difficulty": difficulty,
            "media_paths": media_paths,
        }

    static func from_dict(data: Dictionary) -> TherapyWord:
        var word := TherapyWord.new()
        word.id = data.get("id", "")
        word.display_text = data.get("display_text", "")
        word.phonemes = data.get("phonemes", [])
        word.difficulty = data.get("difficulty", 1)
        word.media_paths = data.get("media_paths", [])
        return word

class ScenarioNode:
    var id: String
    var order_index: int
    var word_id: String

    func _init(_id: String = "", _order: int = 0, _word_id: String = ""):
        id = _id
        order_index = _order
        word_id = _word_id

    func to_dict() -> Dictionary:
        return {
            "id": id,
            "order_index": order_index,
            "word_id": word_id,
        }

class ScenarioVersion:
    var scenario_id: String
    var version_number: int
    var created_at: int
    var author: String
    var notes: String
    var data: Dictionary

    func _init(_scenario_id: String = "", _version_number: int = 1, _author: String = ""):
        scenario_id = _scenario_id
        version_number = _version_number
        author = _author
        created_at = Time.get_unix_time_from_system()
        notes = ""
        data = {}

    func to_dict() -> Dictionary:
        return {
            "scenario_id": scenario_id,
            "version_number": version_number,
            "created_at": created_at,
            "author": author,
            "notes": notes,
            "data": data,
        }

class Scenario:
    var id: String
    var name: String
    var difficulty: int
    var created_at: int
    var updated_at: int
    var nodes: Array[ScenarioNode]
    var notes_after_session: String

    func _init(_id: String = "", _name: String = ""):
        id = _id
        name = _name
        difficulty = 1
        created_at = Time.get_unix_time_from_system()
        updated_at = created_at
        nodes = []
        notes_after_session = ""

    func to_dict() -> Dictionary:
        var serialized_nodes: Array = []
        for node in nodes:
            serialized_nodes.append(node.to_dict())
        return {
            "id": id,
            "name": name,
            "difficulty": difficulty,
            "created_at": created_at,
            "updated_at": updated_at,
            "nodes": serialized_nodes,
            "notes_after_session": notes_after_session,
        }

class SessionLogEntry:
    var scenario_id: String
    var word_id: String
    var attempt_index: int
    var success: bool
    var transcription: String
    var recorded_audio_path: String
    var timestamp: int

    func _init():
        timestamp = Time.get_unix_time_from_system()
        attempt_index = 0
        success = false
        transcription = ""
        recorded_audio_path = ""

    func to_dict() -> Dictionary:
        return {
            "scenario_id": scenario_id,
            "word_id": word_id,
            "attempt_index": attempt_index,
            "success": success,
            "transcription": transcription,
            "recorded_audio_path": recorded_audio_path,
            "timestamp": timestamp,
        }
