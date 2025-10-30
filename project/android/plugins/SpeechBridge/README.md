# SpeechBridge Android Plugin

This plugin exposes Android's `SpeechRecognizer` and `TextToSpeech` APIs to the Godot runtime.

## Building

Use Godot's Android custom plugin pipeline:

```bash
./gradlew :SpeechBridge:assemble
```

Copy the generated AAR into `project/android/plugins` and enable it in the Godot editor under **Project > Export > Android > Plugins**.

## Permissions

The plugin automatically requests the `RECORD_AUDIO` permission at runtime. Ensure your export preset includes the permission as well.
