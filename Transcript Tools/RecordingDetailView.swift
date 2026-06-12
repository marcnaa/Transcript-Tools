import SwiftUI

struct RecordingDetailView: View {
    @Bindable var controller: AppController
    let recording: MediaRecording
    @State private var renameTarget: MediaRecording?

    private var transcriptText: String {
        if let result = recording.transcriptResult {
            return result.segments
                .compactMap { segment in
                    guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { return nil }
                    return controller.includeTimestamps
                        ? "[\(controller.formatClock(segment.start))] \(text)"
                        : text
                }
                .joined(separator: "\n")
        }

        if controller.activeOutputRecordingID == recording.id {
            return controller.currentOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailHeader

                MediaPlayerView(recording: recording)

                if recording.status == .completed || !transcriptText.isEmpty {
                    TranscriptReader(text: transcriptText)
                } else {
                    PendingTranscriptView(
                        isRunning: controller.isRunning,
                        canStart: controller.isSelectedModelReady,
                        startAction: { controller.startOrCancel() }
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            DetailBottomBar(controller: controller, recording: recording, transcriptText: transcriptText)
        }
        .sheet(item: $renameTarget) { recording in
            RenameRecordingSheet(controller: controller, recording: recording)
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    StatusPill(
                        title: recording.mediaKind == .video ? "Video" : "Audio",
                        systemImage: recording.mediaKind == .video ? "play.rectangle.fill" : "waveform",
                        tint: recording.mediaKind == .video ? BrandTheme.secondaryAccent : BrandTheme.primaryAccent
                    )

                    StatusPill(
                        title: statusText,
                        systemImage: statusSymbol,
                        tint: statusTint
                    )
                }

                Text(recording.displayName)
                    .font(.system(size: 34, weight: .semibold))
                    .lineLimit(2)

                Text("\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(durationText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    renameTarget = recording
                } label: {
                    Label("Renombrar", systemImage: "pencil")
                }

                Button {
                    copyTranscript()
                } label: {
                    Label("Copiar transcript", systemImage: "doc.on.doc")
                }
                .disabled(transcriptText.isEmpty)

                Button {
                    controller.exportTranscript(for: recording)
                } label: {
                    Label("Exportar Markdown", systemImage: "square.and.arrow.down")
                }
                .disabled(recording.transcriptResult == nil)

                Divider()

                Button(role: .destructive) {
                    controller.deleteRecording(recording)
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
                .disabled(controller.isRunning)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .glassControl()
            .help("Más acciones")
        }
    }

    private var durationText: String {
        guard recording.duration > 0 else { return "Duración pendiente" }
        return controller.formatDuration(recording.duration)
    }

    private var statusText: String {
        switch recording.status {
        case .completed:
            return "Transcrito"
        case .pending:
            return "Pendiente"
        case .converting:
            return "Preparando"
        case .transcribing, .analyzingVideo:
            return "Transcribiendo"
        case .error:
            return "Error"
        case .canceled:
            return "Cancelado"
        }
    }

    private var statusSymbol: String {
        switch recording.status {
        case .completed:
            return "checkmark.circle.fill"
        case .pending:
            return "clock"
        case .converting, .transcribing, .analyzingVideo:
            return "waveform"
        case .error:
            return "exclamationmark.triangle.fill"
        case .canceled:
            return "xmark.circle"
        }
    }

    private var statusTint: Color {
        switch recording.status {
        case .completed:
            return BrandTheme.primaryAccent
        case .pending, .canceled:
            return .secondary
        case .converting, .transcribing, .analyzingVideo:
            return .orange
        case .error:
            return .red
        }
    }

    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(transcriptText, forType: .string)
        controller.log("Transcript copiado al portapapeles.")
    }
}

private struct TranscriptReader: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Transcript", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Text("\(text.count) caracteres")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(text.isEmpty ? "Transcript vacío." : text)
                .font(.system(size: 14, design: .rounded))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appPanel(padding: 20)
    }
}

private struct PendingTranscriptView: View {
    let isRunning: Bool
    let canStart: Bool
    let startAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isRunning ? "waveform" : "text.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(isRunning ? BrandTheme.primaryAccent : .secondary)

            Text(isRunning ? "Transcripción en curso" : "Sin transcript todavía")
                .font(.title3.weight(.semibold))

            Text(promptText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !isRunning {
                Button(action: startAction) {
                    Label("Transcribir pendientes", systemImage: "waveform")
                }
                .controlSize(.large)
                .glassProminentControl()
                .disabled(!canStart)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .appPanel(padding: 20)
    }

    private var promptText: String {
        if isRunning {
            return "El texto aparecerá aquí cuando el modelo termine."
        }

        if !canStart {
            return "Prepara el modelo local desde Ajustes para generar el texto."
        }

        return "Usa Transcribir para generar el texto localmente."
    }
}

private struct DetailBottomBar: View {
    @Bindable var controller: AppController
    let recording: MediaRecording
    let transcriptText: String

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                controller.openOutputDirectory()
            } label: {
                Label("Salida", systemImage: "folder")
            }
            .glassControl()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(transcriptText, forType: .string)
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            .glassControl()
            .disabled(transcriptText.isEmpty)

            Button {
                controller.exportTranscript(for: recording)
            } label: {
                Label("Exportar", systemImage: "square.and.arrow.down")
            }
            .glassControl()
            .disabled(recording.transcriptResult == nil)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
