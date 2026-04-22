import Foundation
import AVFoundation
import Speech


@MainActor
class VoiceCommandManager: ObservableObject {
    @Published var isListening = false
    @Published var lastHeardWord = ""
    @Published var showSettingsAlert = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Command control state

    private var lastExecutedWord: String = ""
    private var lastExecutionTime: Date = .distantPast
    private let executionCooldown: TimeInterval = 1.0   // human feedback loop

    var onPlay: (() -> Void)?
    var onStop: (() -> Void)?
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?

    func requestPermissionsAndStart() {
#if os(iOS)
        let micStatus = AVAudioApplication.shared.recordPermission
        switch micStatus {
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    guard allowed else {
                        self?.showSettingsAlert = true
                        return
                    }
                    self?.requestSpeechAndStart()
                }
            }
        case .granted:
            requestSpeechAndStart()
        case .denied:
            showSettingsAlert = true
        @unknown default:
            requestSpeechAndStart()
        }
#else
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.startListening()
                }
            }
        }
#endif
    }

#if os(iOS)
    private func requestSpeechAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.startListening()
                } else {
                    self?.showSettingsAlert = true
                }
            }
        }
    }
#endif

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        stopListening()

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
#endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)

        guard inputFormat.channelCount > 0 else {
            print("No audio input available")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                let words = text.split(separator: " ")
                guard let last = words.last else { return }
                let word = String(last)

                // -------------------------
                // LIVE UI UPDATE (always)
                // -------------------------
                DispatchQueue.main.async {
                    self.lastHeardWord = word
                }

                // -------------------------
                // EXECUTION GATE
                // -------------------------

                let now = Date()

                let isStateCommand = (
                    word == "stop" ||
                    word == "pause" ||
                    word == "play" ||
                    word == "start" ||
                    word == "skip" ||
                    word == "back"
                )

                guard isStateCommand else { return }

                if word == self.lastExecutedWord,
                   now.timeIntervalSince(self.lastExecutionTime) < self.executionCooldown {
                    return
                }

                self.lastExecutedWord = word
                self.lastExecutionTime = now

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    switch word {
                    case "stop", "pause":
                        self.onStop?()
                    case "play", "start":
                        self.onPlay?()
                    case "back":
                        self.onBack?()
                    case "skip":
                        self.onSkip?()
                    default:
                        break
                    }
                }
            }

            if error != nil {
                self.stopListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startListening()
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()

        print("Audio engine started: \(audioEngine.isRunning)")
        isListening = true
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        isListening = false
    }
}
