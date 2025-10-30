class_name WhisperFallback
extends RefCounted

const WHISPER_ENDPOINT := "http://127.0.0.1:9000/transcribe"
const WHISPER_TTS_ENDPOINT := "http://127.0.0.1:9000/speak"

var _http := HTTPRequest.new()
var _speech_service

func _init() -> void:
    if Engine.get_main_loop() is SceneTree:
        var tree := Engine.get_main_loop() as SceneTree
        tree.root.call_deferred("add_child", _http)

func bind_service(service) -> void:
    _speech_service = service

func recognize_async() -> void:
    if not _http.is_inside_tree():
        push_error("HTTPRequest node not in scene tree; Whisper fallback disabled")
        return
    if not _http.request_completed.is_connected(Callable(self, "_on_request_completed")):
        _http.request_completed.connect(Callable(self, "_on_request_completed"), CONNECT_ONE_SHOT)
    var err := _http.request(WHISPER_ENDPOINT)
    if err != OK:
        _speech_service.emit_event({"type": "error", "message": "Whisper request failed"})

func speak_async(text: String) -> void:
    if not _http.is_inside_tree():
        return
    var headers := ["Content-Type: application/json"]
    var body := JSON.stringify({"text": text})
    _http.request(WHISPER_TTS_ENDPOINT, headers, HTTPClient.METHOD_POST, body)
    if _speech_service:
        _speech_service.emit_event({"type": "tts_complete"})

func _on_request_completed(_result, response_code, _headers, body) -> void:
    if response_code != 200:
        _speech_service.emit_event({"type": "error", "message": "Whisper returned %d" % response_code})
        return
    var parsed := JSON.parse_string(body.get_string_from_utf8())
    if typeof(parsed) == TYPE_DICTIONARY and parsed.has("text"):
        _speech_service.emit_event({"type": "transcription", "text": parsed["text"]})
        _speech_service.emit_event({"type": "listening", "active": false})
    else:
        _speech_service.emit_event({"type": "error", "message": "Invalid Whisper response"})
