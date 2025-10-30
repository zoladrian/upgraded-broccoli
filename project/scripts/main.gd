extends Node2D

const SpeechService = preload("res://scripts/speech_service.gd")

@onready var speech_service: SpeechService = SpeechService.new()
var recognizing := false

func _ready() -> void:
    speech_service.events.connect(_on_speech_event)
    speech_service.initialize()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") or event is InputEventScreenTouch and event.is_pressed():
        if recognizing:
            speech_service.stop_listening()
        else:
            speech_service.start_listening()

func _on_speech_event(event: Dictionary) -> void:
    match event.get("type"):
        "transcription":
            $Label.text = event.get("text", "")
        "error":
            $Label.text = "Error: %s" % event.get("message", "unknown")
        "listening":
            recognizing = event.get("active", false)
            $Label.text = recognizing ? "Listening..." : "Tap to start speech recognition"
        "tts_complete":
            recognizing = false
