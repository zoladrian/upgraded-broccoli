# SpeechBridge iOS Plugin

This folder contains a Swift-based Godot native script that exposes iOS speech APIs. Build it as part of an iOS module using the Godot iOS plugin template and add the resulting framework to the export templates.

## Files
- `SpeechBridge.swift` – Native bridge that coordinates `SFSpeechRecognizer` and `AVSpeechSynthesizer`.

## Integration steps
1. Install the [godot-ios-plugins](https://github.com/godotengine/godot-ios-plugins) tooling.
2. Create a plugin manifest referencing this Swift file and include it in the Xcode project generated during export.
3. Ensure the following capabilities are enabled in your project:
   - Speech Recognition
   - Microphone
4. Add the `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` keys to your `Info.plist`. The export preset already defines the descriptive strings.
