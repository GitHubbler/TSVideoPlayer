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

// MARK: - Voice Command Manager

@MainActor
class VoiceCommandManager: ObservableObject {
    @Published var isListening = false
    @Published var lastHeardWord = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var onPlay: (() -> Void)?
    var onStop: (() -> Void)?
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?

    func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.startListening()
                }
            }
        }
    }

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }
        stopListening()

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
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
                        if word == "stop" || word == "pause" {
                            self.onStop?()
                        } else if word == "play" || word == "start" {
                            self.onPlay?()
                        } else if word == "back" {
                            self.onBack?()
                        } else if word == "skip" {
                            self.onSkip?()
                        }
                    }
                }
            }
            if error != nil || (result?.isFinal == true) {
                DispatchQueue.main.async {
                    self.stopListening()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.isListening { return }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var title = "Video Player"
    @StateObject private var voiceManager = VoiceCommandManager()
    #if os(iOS)
    @State private var showFilePicker = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: player)
                .background(Color.black)

            HStack {
                Button(action: toggleVoiceControl) {
                    Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.slash")
                }
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
                }
                #endif

                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                #if os(macOS)
                .keyboardShortcut(.space, modifiers: [])
                #endif

                Spacer()

                Color.clear
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        .focusedSceneValue(\.openVideo, openFile)
        #endif
        .navigationTitle(title)
        #if os(iOS)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                title = url.lastPathComponent
                player.play()
                isPlaying = true
                url.stopAccessingSecurityScopedResource()
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            isPlaying = false
        }
        .onAppear {
            voiceManager.onPlay = { [self] in
                if player.timeControlStatus != .playing {
                    player.play()
                    isPlaying = true
                }
            }
            voiceManager.onStop = { [self] in
                if player.timeControlStatus == .playing {
                    player.pause()
                    isPlaying = false
                }
            }
            voiceManager.onBack = { [self] in
                let current = player.currentTime()
                let target = CMTimeSubtract(current, CMTime(seconds: 15, preferredTimescale: 600))
                player.seek(to: CMTimeMaximum(target, .zero))
            }
            voiceManager.onSkip = { [self] in
                let current = player.currentTime()
                let target = CMTimeAdd(current, CMTime(seconds: 15, preferredTimescale: 600))
                player.seek(to: target)
            }
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
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            title = url.lastPathComponent
            player.play()
            isPlaying = true
        }
    }
    #endif

    private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
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