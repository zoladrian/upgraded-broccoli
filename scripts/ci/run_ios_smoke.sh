#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="$(dirname "$0")/../../project"
EXPORT_PRESET="iOS"
BUILD_DIR="${PROJECT_PATH}/build/ios"
APP_PATH="${BUILD_DIR}/CrossPlatformSpeech.app"

mkdir -p "${BUILD_DIR}"

godot4 --headless --path "${PROJECT_PATH}" --export-release "${EXPORT_PRESET}" "${BUILD_DIR}"

xcodebuild -project "${BUILD_DIR}/CrossPlatformSpeech.xcodeproj" -scheme CrossPlatformSpeech -configuration Release -destination 'platform=iOS Simulator,name=iPhone 15' build

xcrun simctl boot "iPhone 15"
xcrun simctl install booted "${APP_PATH}"
xcrun simctl launch booted com.example.crossplatformspeech
sleep 10
xcrun simctl terminate booted com.example.crossplatformspeech
xcrun simctl spawn booted log show --style compact --predicate 'process == "CrossPlatformSpeech"' --last 5m
