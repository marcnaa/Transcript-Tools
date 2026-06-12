import SwiftUI

struct RecordingStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: AppController
    @State private var recorder = RecordingSessionController()
    @State private var recordingTitle = Self.defaultTitle()
    @State private var isImporting = false

    var body: some View {
        @Bindable var recorder = recorder

        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nueva grabación")
                        .font(.title2.weight(.semibold))

                    Text(recorder.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .disabled(recorder.isRecording || recorder.isBusy || isImporting)
                .help("Cerrar")
            }

            Picker("Fuente", selection: $recorder.source) {
                ForEach(RecordingSource.allCases) { source in
                    Label(source.title, systemImage: source.iconName)
                        .tag(source)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recorder.isRecording || recorder.isBusy || isImporting)

            RecordingStageView(source: recorder.source, elapsed: recorder.elapsed, isRecording: recorder.isRecording)

            TextField("Nombre de la grabación", text: $recordingTitle)
                .textFieldStyle(.roundedBorder)
                .disabled(recorder.isRecording || recorder.isBusy || isImporting)

            if let failureMessage = recorder.failureMessage {
                RecordingFailureView(message: failureMessage, source: recorder.source) {
                    recorder.discardFailure()
                }
            }

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .disabled(recorder.isRecording || recorder.isBusy || isImporting)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if recorder.isRecording {
                    Button {
                        Task { await stopAndImport() }
                    } label: {
                        Label("Detener", systemImage: "stop.fill")
                    }
                    .glassProminentControl()
                    .tint(.red)
                    .disabled(isImporting)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        Task { await recorder.start() }
                    } label: {
                        Label("Grabar", systemImage: "record.circle")
                    }
                    .glassProminentControl()
                    .tint(.red)
                    .disabled(recorder.isBusy || isImporting)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(BrandTheme.contentBackground)
        .interactiveDismissDisabled(recorder.isRecording || recorder.isBusy || isImporting)
    }

    private func stopAndImport() async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard let recordedURL = try await recorder.stop() else { return }
            let importURL = try Self.namedImportURL(from: recordedURL, title: recordingTitle)
            controller.addFiles(urls: [importURL])
            try? FileManager.default.removeItem(at: importURL)
            dismiss()
        } catch {
            // The recorder already presents the failure state.
        }
    }

    private static func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Grabación \(formatter.string(from: Date()))"
    }

    private static func namedImportURL(from url: URL, title: String) throws -> URL {
        let filename = safeFilename(from: title)
        let destination = url.deletingLastPathComponent().appendingPathComponent("\(filename).m4a")

        guard destination.standardizedFileURL != url.standardizedFileURL else {
            return url
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    private static func safeFilename(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = trimmed.components(separatedBy: allowed.inverted).joined()
        let normalized = cleaned.replacingOccurrences(of: " ", with: "_")
        return normalized.isEmpty ? defaultTitle().replacingOccurrences(of: " ", with: "_") : normalized
    }
}

private struct RecordingStageView: View {
    let source: RecordingSource
    let elapsed: TimeInterval
    let isRecording: Bool

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.red.opacity(isRecording ? 0.14 : 0.08))

                Image(systemName: source.iconName)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isRecording ? .red : .secondary)
            }
            .frame(width: 118, height: 118)

            Text(formatElapsed(elapsed))
                .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())

            RecordingWaveformView(isRecording: isRecording)
                .frame(height: 42)
        }
        .frame(maxWidth: .infinity)
        .appPanel(padding: 24)
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct RecordingWaveformView: View {
    let isRecording: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<32, id: \.self) { index in
                    Capsule()
                        .fill(isRecording ? Color.red.opacity(0.72) : Color.secondary.opacity(0.26))
                        .frame(width: 4, height: barHeight(index: index, date: timeline.date))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        guard isRecording else {
            return CGFloat(8 + (index % 5) * 3)
        }

        let phase = date.timeIntervalSinceReferenceDate * 4.2 + Double(index) * 0.46
        let amplitude = (sin(phase) + 1) / 2
        return CGFloat(8 + amplitude * 30)
    }
}

private struct RecordingFailureView: View {
    let message: String
    let source: RecordingSource
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)

                HStack {
                    Button {
                        openPrivacySettings()
                    } label: {
                        Label("Abrir permisos", systemImage: "switch.2")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Cerrar") {
                        dismissAction()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.orange.opacity(0.22), lineWidth: 1)
        }
    }

    private func openPrivacySettings() {
        let pane: String

        switch source {
        case .microphone:
            pane = "Privacy_Microphone"
        case .systemAudio:
            if let micURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(micURL)
            }
            pane = "Privacy_ScreenCapture"
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    RecordingStudioView(controller: AppController())
}
