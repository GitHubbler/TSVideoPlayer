import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Speech

// MARK: - Focused Values

#if os(macOS)
struct OpenVideoKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openVideo: (() -> Void)? {
        get { self[OpenVideoKey.self] }
        set { self[OpenVideoKey.self] = newValue }
    }
}
#endif

// MARK: - App

@main
struct VideoPlayerApp: App {
#if os(macOS)
    @FocusedValue(\.openVideo) var openVideo
#endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
#if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video...") {
                    openVideo?()
                }
                .keyboardShortcut("o")
            }
        }
#endif
    }
}

// MARK: - Player Model

@MainActor
class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published var title = "Video Player"
#if os(iOS)
    var activeURL: URL?
#endif
    
    private static let lastURLKey = "LastOpenedVideoURL"
    
    init() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
    }
    
    func play() {
        player.play()
        isPlaying = true
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }
    
    func load(url: URL) {
#if os(iOS)
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = url
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
        UserDefaults.standard.set(url.path, forKey: Self.lastURLKey)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        title = url.lastPathComponent
        play()
    }
    
    func restoreLastURL() {
        guard let path = UserDefaults.standard.string(forKey: Self.lastURLKey) else { return }
        let url = URL(fileURLWithPath: path)
        
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        title = url.lastPathComponent
        
        pause()
    }
    
    func seek(by seconds: Double) {
        let current = player.currentTime()
        if seconds < 0 {
            let target = CMTimeSubtract(current, CMTime(seconds: -seconds, preferredTimescale: 600))
            player.seek(to: CMTimeMaximum(target, .zero))
        } else {
            let target = CMTimeAdd(current, CMTime(seconds: seconds, preferredTimescale: 600))
            player.seek(to: target)
        }
    }
#if os(iOS)
    func releaseURL() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
    }
#endif
}

// MARK: - Voice Command Manager

@MainActor
class VoiceCommandManager: ObservableObject {
    @Published var isListening = false
    @Published var lastHeardWord = ""
    @Published var showSettingsAlert = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var lastProcessedTranscript: String = ""
    private var lastEmittedWord: String = ""
    private var lastCommandTime: Date = .distantPast
    private let commandCooldown: TimeInterval = 0.8
    
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
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default,
                                     options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
#endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Reset state for a fresh session
        self.lastProcessedTranscript = ""
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)

        // Verify input node is available
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
                print("Got recognition result")
                let text = result.bestTranscription.formattedString.lowercased()
                print("TEXT:", text)

                let words = text.split(separator: " ")
                guard let last = words.last else { return }
                let word = String(last)

                // Avoid emitting same word repeatedly
                guard word != self.lastEmittedWord else { return }
                self.lastEmittedWord = word

                let now = Date()
                guard now.timeIntervalSince(self.lastCommandTime) > self.commandCooldown else { return }
                self.lastCommandTime = now

                DispatchQueue.main.async {
                    self.lastHeardWord = word
                    switch word {
                    case "stop", "pause": self.onStop?()
                    case "play", "start": self.onPlay?()
                    case "back": self.onBack?()
                    case "skip": self.onSkip?()
                    default: break
                    }
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.stopListening()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startListening()
                    }
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
        print("Audio engine started: \(self.audioEngine.isRunning)")
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

// MARK: - Content View

struct ContentView: View {
    @StateObject private var model = PlayerModel()
    @StateObject private var voiceManager = VoiceCommandManager()
#if os(iOS)
    @State private var showFilePicker = false
#endif
#if os(macOS)
    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            model.load(url: url)
        }
    }
#endif
    
    var body: some View {
        VStack {
            PlayerView(player: model.player)
                .background(Color.black)
            
            HStack {
                Button(action: toggleVoiceControl) {
                    Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.slash")
                }
                
                if voiceManager.isListening {
                    Text(voiceManager.lastHeardWord)
                }
                
                Spacer()
                
                Button(action: model.togglePlayPause) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .padding()
        }
        .onAppear {
            voiceManager.onPlay = { model.play() }
            voiceManager.onStop = { model.pause() }
            voiceManager.onBack = { model.seek(by: -15) }
            voiceManager.onSkip = { model.seek(by: 15) }
            model.restoreLastURL()
        }
#if os(macOS)
        .focusedSceneValue(\.openVideo, openVideo)
#endif
    }
    
    private func toggleVoiceControl() {
        if voiceManager.isListening {
            voiceManager.stopListening()
        } else {
            voiceManager.requestPermissionsAndStart()
        }
    }
}

// MARK: - Player View

#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer = layer
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
