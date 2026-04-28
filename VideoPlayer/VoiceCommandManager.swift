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
    private var restartWorkItem: DispatchWorkItem?
    private var clearLastHeardWordWorkItem: DispatchWorkItem?
    private var wantsListening = false
    private var suppressErrorHandlingUntil: Date = .distantPast

    // MARK: - Command control state

    private var lastExecutedWord: String = ""
    private var lastExecutionTime: Date = .distantPast
    private let executionCooldown: TimeInterval = 1.0   // human feedback loop
    private let commandRearmDelay: TimeInterval = 0.15

    var onPlay: (() -> Void)?
    var onStop: (() -> Void)?
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onFast: (() -> Void)?
    var onSlow: (() -> Void)?
    var onLoud: (() -> Void)?
    var onSoft: (() -> Void)?

    func requestPermissionsAndStart() {
        wantsListening = true
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
        wantsListening = true
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        restartWorkItem?.cancel()
        tearDownRecognitionSession()

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
#endif

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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                guard let segment = result.bestTranscription.segments.last else { return }
                let word = segment.substring
                    .lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)

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
                    word == "back" ||
                    word == "begin" ||
                    word == "end" ||
                    word == "fast" ||
                    word == "slow" ||
                    word == "loud" ||
                    word == "soft"
                )

                guard isStateCommand else { return }

                if word == self.lastExecutedWord,
                   now.timeIntervalSince(self.lastExecutionTime) < self.executionCooldown {
                    return
                }

                self.lastExecutedWord = word
                self.lastExecutionTime = now
                self.scheduleLastHeardWordClear()

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
                    case "begin":
                        self.onBegin?()
                    case "end":
                        self.onEnd?()
                    case "fast":
                        self.onFast?()
                    case "slow":
                        self.onSlow?()
                    case "loud":
                        self.onLoud?()
                    case "soft":
                        self.onSoft?()
                    default:
                        break
                    }
                }

                self.rearmRecognitionForNextCommand()
            }

            if error != nil {
                let now = Date()
                if now < self.suppressErrorHandlingUntil {
                    return
                }

                self.tearDownRecognitionSession()
                guard self.wantsListening else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.wantsListening else { return }
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
        wantsListening = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        clearLastHeardWordWorkItem?.cancel()
        clearLastHeardWordWorkItem = nil
        suppressErrorHandlingUntil = Date().addingTimeInterval(1.0)
        lastExecutedWord = ""
        lastExecutionTime = .distantPast
        lastHeardWord = ""
        tearDownRecognitionSession()
    }

    private func rearmRecognitionForNextCommand() {
        guard wantsListening else { return }

        restartWorkItem?.cancel()
        suppressErrorHandlingUntil = Date().addingTimeInterval(1.0)
        tearDownRecognitionSession()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.wantsListening else { return }
            self.startListening()
        }

        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + commandRearmDelay, execute: workItem)
    }

    private func scheduleLastHeardWordClear() {
        clearLastHeardWordWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastHeardWord = ""
        }

        clearLastHeardWordWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + executionCooldown, execute: workItem)
    }

    private func tearDownRecognitionSession() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}
