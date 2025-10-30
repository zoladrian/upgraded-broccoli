class_name SpeechService
extends RefCounted

const WhisperFallback = preload("res://addons/whisper/whisper_fallback.gd")

signal events(event: Dictionary)

var _platform_impl: SpeechPlatformAdapter
var _fallback: WhisperFallback

func _init() -> void:
    _fallback = WhisperFallback.new()
    _fallback.bind_service(self)
    match OS.get_name():
        "Android":
            _platform_impl = AndroidSpeechAdapter.new(self)
        "iOS":
            _platform_impl = IOSSpeechAdapter.new(self)
        _:
            _platform_impl = DesktopSpeechAdapter.new(self)

func initialize() -> void:
    if _platform_impl:
        _platform_impl.initialize()

func start_listening() -> void:
    if _platform_impl and _platform_impl.start_listening():
        return
    emit_event({"type": "listening", "active": true})
    _fallback.recognize_async()

func stop_listening() -> void:
    if _platform_impl:
        _platform_impl.stop_listening()
    emit_event({"type": "listening", "active": false})

func speak(text: String) -> void:
    if not _platform_impl or not _platform_impl.speak(text):
        _fallback.speak_async(text)

func emit_event(event: Dictionary) -> void:
    events.emit(event)

class SpeechPlatformAdapter:
    var owner: SpeechService
    func _init(service: SpeechService) -> void:
        owner = service
    func initialize() -> void:
        pass
    func start_listening() -> bool:
        return false
    func stop_listening() -> void:
        pass
    func speak(_text: String) -> bool:
        return false

class DesktopSpeechAdapter extends SpeechPlatformAdapter:
    func start_listening() -> bool:
        owner.emit_event({"type": "error", "message": "Speech recognition not available"})
        return false

class AndroidSpeechAdapter extends SpeechPlatformAdapter:
    var bridge_singleton

    func initialize() -> void:
        var plugin := Engine.get_singleton("SpeechBridge")
        if plugin:
            bridge_singleton = plugin
            if plugin.has_signal("onSpeechEvent"):
                plugin.connect("onSpeechEvent", Callable(self, "_on_bridge_event"))
        else:
            owner.emit_event({"type": "error", "message": "SpeechBridge plugin missing"})

    func start_listening() -> bool:
        if not bridge_singleton:
            return false
        bridge_singleton.call("startListening")
        owner.emit_event({"type": "listening", "active": true})
        return true

    func stop_listening() -> void:
        if bridge_singleton:
            bridge_singleton.call("stopListening")
            owner.emit_event({"type": "listening", "active": false})

    func speak(text: String) -> bool:
        if not bridge_singleton:
            return false
        bridge_singleton.call("speak", text)
        return true

    func _on_bridge_event(payload) -> void:
        if typeof(payload) == TYPE_DICTIONARY:
            owner.emit_event(payload)
        elif typeof(payload) == TYPE_STRING:
            var parsed := JSON.parse_string(payload)
            if typeof(parsed) == TYPE_DICTIONARY:
                owner.emit_event(parsed)

class IOSSpeechAdapter extends SpeechPlatformAdapter:
    func initialize() -> void:
        if not Engine.has_singleton("SpeechBridge"):
            owner.emit_event({"type": "error", "message": "SpeechBridge singleton missing"})
        else:
            var bridge := Engine.get_singleton("SpeechBridge")
            if bridge.has_signal("onSpeechEvent"):
                bridge.connect("onSpeechEvent", Callable(self, "_on_bridge_event"))

    func start_listening() -> bool:
        if not Engine.has_singleton("SpeechBridge"):
            return false
        Engine.get_singleton("SpeechBridge").startListening()
        owner.emit_event({"type": "listening", "active": true})
        return true

    func stop_listening() -> void:
        if Engine.has_singleton("SpeechBridge"):
            Engine.get_singleton("SpeechBridge").stopListening()
            owner.emit_event({"type": "listening", "active": false})

    func speak(text: String) -> bool:
        if not Engine.has_singleton("SpeechBridge"):
            return false
        Engine.get_singleton("SpeechBridge").speak(text)
        return true

    func _on_bridge_event(payload) -> void:
        if typeof(payload) == TYPE_DICTIONARY:
            owner.emit_event(payload)
