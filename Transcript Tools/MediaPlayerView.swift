import AVFoundation
import AVKit
import Combine
import SwiftUI

struct MediaPlayerView: View {
    let recording: MediaRecording

    var body: some View {
        Group {
            switch recording.mediaKind {
            case .audio:
                AudioMemoPlayer(url: recording.sourceURL, title: recording.displayName)
            case .video:
                VideoPlayerCard(url: recording.sourceURL)
            }
        }
    }
}

private struct VideoPlayerCard: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        NativeAVPlayerView(player: player)
            .frame(minHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrandTheme.border, lineWidth: 1)
            }
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
            }
            .onChange(of: url) {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
            }
            .onDisappear {
                player.pause()
            }
    }
}

private struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.allowsVideoFrameAnalysis = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct AudioMemoPlayer: View {
    let url: URL
    let title: String

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .background(BrandTheme.primaryAccent, in: Circle())
            .help(isPlaying ? "Pausar" : "Reproducir")

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formatTime(currentTime))
                    Slider(value: progressBinding)
                    Text(formatTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .appPanel(padding: 18)
        .onAppear {
            configurePlayer()
        }
        .onChange(of: url) {
            configurePlayer()
        }
        .onDisappear {
            player.pause()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
            if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
            isPlaying = player.timeControlStatus == .playing
        }
    }

    private var progressBinding: Binding<Double> {
        Binding {
            guard duration > 0 else { return 0 }
            return min(max(currentTime / duration, 0), 1)
        } set: { newValue in
            guard duration > 0 else { return }
            let target = newValue * duration
            currentTime = target
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
    }

    private func configurePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        isPlaying = false
        currentTime = 0
        duration = 0

        Task {
            let asset = AVURLAsset(url: url)
            if let loadedDuration = try? await asset.load(.duration).seconds, loadedDuration.isFinite {
                await MainActor.run {
                    duration = loadedDuration
                }
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
