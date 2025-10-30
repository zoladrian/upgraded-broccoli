extends AndroidPlugin

signal onSpeechEvent(payload)

const PLUGIN_NAME := "SpeechBridge"

func _init() -> void:
    register_plugin()

func get_plugin_name() -> String:
    return PLUGIN_NAME

func get_plugin_methods() -> PackedStringArray:
    return PackedStringArray(["startListening", "stopListening", "speak"])

func startListening() -> void:
    if is_plugin_initialized():
        java_call("startListening")

func stopListening() -> void:
    if is_plugin_initialized():
        java_call("stopListening")

func speak(text: String) -> void:
    if is_plugin_initialized():
        java_call("speak", text)

func onMainCreate() -> void:
    if is_plugin_initialized():
        java_call("onMainCreate")

func handle_signal(payload) -> void:
    emit_signal("onSpeechEvent", payload)
