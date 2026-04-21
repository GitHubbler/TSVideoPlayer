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
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        title = url.lastPathComponent
        play()
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
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                let words = text.split(separator: " ")
                if let last = words.last {
                    let word = String(last)
                    DispatchQueue.main.async {
                        self.lastHeardWord = word
                        switch word {
                        case "stop", "pause": self.onStop?()
                        case "play", "start": self.onPlay?()
                        case "back":           self.onBack?()
                        case "skip":           self.onSkip?()
                        default: break
                        }
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.stopListening()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !self.isListening else { return }
                        self.startListening()
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            stopListening()
        }
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var model = PlayerModel()
    @StateObject private var voiceManager = VoiceCommandManager()
    #if os(iOS)
    @State private var showFilePicker = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: model.player)
                .background(Color.black)

            HStack {
                Button(action: toggleVoiceControl) {
                    Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.slash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .contentShape(Rectangle())
                #if os(macOS)
                .help(voiceManager.isListening ? "Voice control active" : "Enable voice control")
                #endif

                if voiceManager.isListening && !voiceManager.lastHeardWord.isEmpty {
                    Text(voiceManager.lastHeardWord)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                #if os(iOS)
                Button(action: { showFilePicker = true }) {
                    Image(systemName: "folder")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .contentShape(Rectangle())
                #endif

                Button(action: model.togglePlayPause) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .contentShape(Rectangle())
                #if os(macOS)
                .keyboardShortcut(.space, modifiers: [])
                #endif

                Spacer()

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        .focusedSceneValue(\.openVideo, openFile)
        #endif
        .navigationTitle(model.title)
        #if os(iOS)
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                model.load(url: url)
            }
        }
        .alert("Microphone Access Required",
               isPresented: $voiceManager.showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Voice control needs microphone and speech recognition access. Please enable both in Settings > Privacy.")
        }
        .onDisappear {
            model.releaseURL()
        }
        #endif
        .onAppear {
            voiceManager.onPlay  = { [weak model] in model?.play() }
            voiceManager.onStop  = { [weak model] in model?.pause() }
            voiceManager.onBack  = { [weak model] in model?.seek(by: -15) }
            voiceManager.onSkip  = { [weak model] in model?.seek(by:  15) }
        }
    }

    private func toggleVoiceControl() {
        if voiceManager.isListening {
            voiceManager.stopListening()
        } else {
            voiceManager.requestPermissionsAndStart()
        }
    }

    #if os(macOS)
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.load(url: url)
        }
    }
    #endif
}

// MARK: - Player View

#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.player = player
    }

    class PlayerNSView: NSView {
        private let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(playerLayer)
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}
#else
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }

    class PlayerUIView: UIView {
        private let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(playerLayer)
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
#endif