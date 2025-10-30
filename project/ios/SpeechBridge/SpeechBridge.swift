import Foundation
import Speech
import AVFoundation
import Godot

@objc(SpeechBridge)
class SpeechBridge: NSObject, GodotNativeScript, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    var speechRecognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioEngine = AVAudioEngine()
    let speechSynthesizer = AVSpeechSynthesizer()
    var godotObject: GodotNativeScriptInstance?

    required override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer()
        speechSynthesizer.delegate = self
    }

    func _ready() {
        requestPermissions()
    }

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                self.emit(type: "error", data: ["message": "Speech recognition unauthorized"])
            }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                self.emit(type: "error", data: ["message": "Microphone permission denied"])
            }
        }
    }

    func startListening() {
        if audioEngine.isRunning {
            stopListening()
        }
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        emit(type: "listening", data: ["active": true])

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.emit(type: "transcription", data: ["text": result.bestTranscription.formattedString])
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        emit(type: "listening", data: ["active": false])
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        speechSynthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        emit(type: "tts_complete", data: [:])
    }

    func emit(type: String, data: [String: Any]) {
        var payload = data
        payload["type"] = type
        godotObject?.emit(signal: "onSpeechEvent", arguments: [payload])
    }

    static func create(instance: GodotNativeScriptInstance) -> SpeechBridge {
        let bridge = SpeechBridge()
        bridge.godotObject = instance
        instance.connect(signal: "startListening", to: bridge, method: "startListening")
        instance.connect(signal: "stopListening", to: bridge, method: "stopListening")
        instance.connect(signal: "speak", to: bridge, method: "speak:")
        return bridge
    }

    static func destroy(instance: GodotNativeScriptInstance, script: SpeechBridge) {
        script.audioEngine.stop()
    }
}
