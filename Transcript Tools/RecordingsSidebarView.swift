import SwiftUI

struct RecordingsSidebarView: View {
    @Bindable var controller: AppController
    @Binding var searchText: String
    @State private var renameTarget: MediaRecording?

    private var filteredRecordings: [MediaRecording] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return controller.recordings }

        return controller.recordings.filter { recording in
            recording.displayName.localizedCaseInsensitiveContains(query)
                || recording.originalFilename.localizedCaseInsensitiveContains(query)
                || recording.transcriptText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(selection: $controller.selectedRecordingIDs) {
            Section {
                if filteredRecordings.isEmpty {
                    EmptySidebarRow(hasRecordings: !controller.recordings.isEmpty)
                } else {
                    ForEach(filteredRecordings) { recording in
                        RecordingRow(recording: recording)
                            .tag(recording.id)
                            .contextMenu {
                                Button {
                                    renameTarget = recording
                                } label: {
                                    Label("Renombrar", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    if controller.selectedRecordingIDs.count > 1,
                                       controller.selectedRecordingIDs.contains(recording.id) {
                                        controller.deleteRecordings(ids: controller.selectedRecordingIDs)
                                    } else {
                                        controller.deleteRecording(recording)
                                    }
                                } label: {
                                    Label(deleteLabel(for: recording), systemImage: "trash")
                                }
                                .disabled(controller.isRunning)
                            }
                    }
                    .onDelete { indexSet in
                        let ids = Set(indexSet.map { filteredRecordings[$0].id })
                        controller.deleteRecordings(ids: ids)
                    }
                }
            } header: {
                HStack {
                    Text("Grabaciones")
                    Spacer()
                    Text("\(controller.recordings.count)")
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if controller.isRunning {
                ProcessingStrip(controller: controller)
                    .padding(10)
            } else if controller.selectedRecordingIDs.count > 1 {
                SelectionActionStrip(selectedCount: controller.selectedRecordingIDs.count) {
                    controller.deleteRecordings(ids: controller.selectedRecordingIDs)
                }
                .padding(10)
            }
        }
        .sheet(item: $renameTarget) { recording in
            RenameRecordingSheet(controller: controller, recording: recording)
        }
    }

    private func deleteLabel(for recording: MediaRecording) -> String {
        if controller.selectedRecordingIDs.count > 1,
           controller.selectedRecordingIDs.contains(recording.id) {
            return "Eliminar seleccionadas"
        }

        return "Eliminar"
    }
}

private struct RecordingRow: View {
    let recording: MediaRecording

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconTint.opacity(0.14))

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: recording.mediaKind == .video ? "play.rectangle.fill" : "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("·")
                    Text(durationText)
                    Text("·")
                    Text(statusText)
                        .foregroundStyle(statusTint)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        guard recording.duration > 0 else { return "--:--" }
        let seconds = Int(recording.duration)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    private var statusText: String {
        switch recording.status {
        case .completed:
            return "Transcrito"
        case .pending:
            return "Pendiente"
        case .converting, .transcribing, .analyzingVideo:
            return "Procesando"
        case .error:
            return "Error"
        case .canceled:
            return "Cancelado"
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

    private var iconTint: Color {
        recording.mediaKind == .video ? BrandTheme.secondaryAccent : BrandTheme.primaryAccent
    }

    private var isProcessing: Bool {
        switch recording.status {
        case .converting, .transcribing, .analyzingVideo:
            return true
        case .pending, .completed, .error, .canceled:
            return false
        }
    }
}

private struct EmptySidebarRow: View {
    let hasRecordings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hasRecordings ? "Sin resultados" : "Nada importado")
                .font(.system(size: 13, weight: .semibold))
            Text(hasRecordings ? "Prueba otra búsqueda." : "Usa Importar para crear tu biblioteca.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct ProcessingStrip: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: controller.isRunning ? "waveform" : "checkmark.circle")
                    .foregroundStyle(controller.isRunning ? BrandTheme.primaryAccent : .secondary)
                Text(controller.statusText)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if controller.isRunning {
                    Text("\(Int(controller.overallProgress))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if controller.isRunning {
                ProgressView(value: controller.overallProgress, total: 100)
                    .tint(BrandTheme.primaryAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 10)
    }
}

private struct SelectionActionStrip: View {
    let selectedCount: Int
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("\(selectedCount) seleccionadas", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Label("Eliminar", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 10)
    }
}

struct RenameRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: AppController
    let recording: MediaRecording
    @State private var name: String

    init(controller: AppController, recording: MediaRecording) {
        self.controller = controller
        self.recording = recording
        self._name = State(initialValue: recording.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Renombrar")
                .font(.title3.weight(.semibold))

            TextField("Nombre", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()

                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Guardar") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func save() {
        controller.renameRecording(recording, to: name)
        dismiss()
    }
}
