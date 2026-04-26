import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
//import Speech

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

    func seekToBeginningAndPause() {
        pause()
        player.seek(to: .zero)
    }

    func seekToEndAndPause() {
        pause()

        guard let item = player.currentItem else { return }

        let duration = item.duration
        guard duration.isNumeric && duration.isValid else { return }

        player.seek(to: duration)
    }
#if os(iOS)
    func releaseURL() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
    }
#endif
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
            voiceManager.onBegin = { model.seekToBeginningAndPause() }
            voiceManager.onEnd = { model.seekToEndAndPause() }
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
