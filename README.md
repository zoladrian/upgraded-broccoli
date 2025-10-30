# CrossPlatform Speech Demo

This repository contains a Godot 4 mobile sample that integrates native speech-to-text and text-to-speech capabilities on Android and iOS with an optional Whisper fallback.

## Structure

- `project/` – Godot project files
  - `scenes/Main.tscn` – start scene used for smoke testing
  - `scripts/` – gameplay logic including the shared `SpeechService`
  - `android/plugins/SpeechBridge` – Android native plugin bridging `SpeechRecognizer` and `TextToSpeech`
  - `ios/SpeechBridge` – iOS native bridge using `SFSpeechRecognizer` and `AVSpeechSynthesizer`
  - `addons/whisper` – fallback integration with external Whisper endpoint
- `.github/workflows/` – CI definitions for Android/iOS smoke tests
- `scripts/ci/` – helper scripts referenced by the workflows

## Requirements

- Godot 4.2 or newer with export templates installed
- Android SDK/NDK for mobile builds
- Xcode 15+ for iOS exports

## Whisper fallback

By default the fallback expects a service reachable at `http://127.0.0.1:9000`. Update `whisper_fallback.gd` to point at your deployment.

## Smoke tests

GitHub Actions spin up Android and iOS emulators and launch the exported builds. See the workflow files for details.
