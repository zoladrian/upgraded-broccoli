#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="$(dirname "$0")/../../project"
EXPORT_PRESET="Android"
OUTPUT_APK="${PROJECT_PATH}/build/android/CrossPlatformSpeech.apk"

mkdir -p "${PROJECT_PATH}/build/android"

godot4 --headless --path "${PROJECT_PATH}" --export-release "${EXPORT_PRESET}" "${OUTPUT_APK}"

aabtool --version >/dev/null 2>&1 || true

adb install -r "${OUTPUT_APK}"
adb shell am start -n com.example.crossplatformspeech/org.godotengine.godot.Godot
adb shell pidof com.example.crossplatformspeech
sleep 10
adb logcat -d | grep -i "Godot" | tail -n 200
