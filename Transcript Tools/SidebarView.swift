import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var controller: AppController
    @State private var selectedFileIDs = Set<UUID>()

    let models = ["tiny", "base", "small", "medium", "large-v2", "large-v3"]
    let languages = [
        ("auto", "Auto-detectar"),
        ("es", "Español"),
        ("en", "Inglés"),
        ("ca", "Catalán"),
        ("fr", "Francés"),
        ("de", "Alemán"),
        ("pt", "Portugués"),
        ("it", "Italiano")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            configurationSection
            outputSection
            queueSection
                .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(minWidth: 360, maxWidth: 380)
        .background(BrandTheme.sidebarBackground)
    }

    private var configurationSection: some View {
        SidebarSection(
            title: "Flujo",
            subtitle: "Configura una vez y procesa toda la cola"
        ) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Modelo")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $controller.selectedModel) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .disabled(controller.isRunning)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Idioma")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $controller.selectedLanguage) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .labelsHidden()
                    .disabled(controller.isRunning)
                }
            }

            Label(modelDescription(controller.selectedModel), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var outputSection: some View {
        SidebarSection(title: "Salida") {
            HStack(spacing: 6) {
                FormatToggle("MD", isOn: $controller.outputFormatMD)
                    .onChange(of: controller.outputFormatMD) { controller.ensureOneFormat() }
                FormatToggle("TXT", isOn: $controller.outputFormatTXT)
                    .onChange(of: controller.outputFormatTXT) { controller.ensureOneFormat() }
                FormatToggle("SRT", isOn: $controller.outputFormatSRT)
                    .onChange(of: controller.outputFormatSRT) { controller.ensureOneFormat() }
                FormatToggle("VTT", isOn: $controller.outputFormatVTT)
                    .onChange(of: controller.outputFormatVTT) { controller.ensureOneFormat() }
            }
            .disabled(controller.isRunning)

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Incluir marcas de tiempo", isOn: $controller.includeTimestamps)
                Toggle("Guardar automáticamente al terminar", isOn: $controller.autoSave)
                Toggle("Filtrar silencios", isOn: $controller.useVAD)
            }
            .toggleStyle(.checkbox)
            .disabled(controller.isRunning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Carpeta de salida")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label {
                        Text(shortenPath(controller.outputDirectory.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(BrandTheme.secondaryAccent)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(BrandTheme.softSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(BrandTheme.mutedBorder, lineWidth: 1)
                    }

                    Button(action: chooseOutputDirectory) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Cambiar carpeta de salida")
                    .disabled(controller.isRunning)
                }
            }
        }
    }

    private var queueSection: some View {
        SidebarSection(title: "Cola de archivos") {
            HStack {
                StatusPill(
                    title: "\(controller.files.count) archivos",
                    systemImage: "tray.full",
                    tint: BrandTheme.secondaryAccent
                )

                Spacer()

                if !selectedFileIDs.isEmpty {
                    StatusPill(
                        title: "\(selectedFileIDs.count) seleccionados",
                        systemImage: "checkmark.circle",
                        tint: BrandTheme.primaryAccent
                    )
                }
            }

            Table(controller.files, selection: $selectedFileIDs) {
                TableColumn("Archivo") { file in
                    Text(file.filename)
                        .lineLimit(1)
                }

                TableColumn("Estado") { file in
                    QueueStatusBadge(status: file.status)
                }

                TableColumn("Tamaño") { file in
                    Text(file.fileSizeString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if controller.files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(BrandTheme.secondaryAccent)

                        Text("Cola vacía")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrandTheme.softSurface.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                Button(action: addFilesAction) {
                    Label("Añadir", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandTheme.primaryAccent)
                .disabled(controller.isRunning)

                Button(action: removeSelectedAction) {
                    Label("Quitar", systemImage: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isRunning || selectedFileIDs.isEmpty)

                Button(action: { controller.clearQueue() }) {
                    Label("Limpiar", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isRunning || controller.files.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func addFilesAction() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [
            .mp3, .mpeg4Audio, .wav,
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "ogg")!,
            UTType(filenameExtension: "flac")!,
            UTType(filenameExtension: "aac")!,
            UTType(filenameExtension: "wma")!,
            .mpeg4Movie, .quickTimeMovie,
            UTType(filenameExtension: "mkv")!,
            UTType(filenameExtension: "avi")!,
            UTType(filenameExtension: "webm")!,
            UTType(filenameExtension: "ts")!
        ]

        if openPanel.runModal() == .OK {
            controller.addFiles(urls: openPanel.urls)
        }
    }

    private func removeSelectedAction() {
        let itemsToRemove = controller.files.filter { selectedFileIDs.contains($0.id) }
        controller.removeSelectedFiles(items: itemsToRemove)
        selectedFileIDs.removeAll()
    }

    private func chooseOutputDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Carpeta de salida"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            controller.outputDirectory = url
            controller.log("Carpeta de salida cambiada a: \(url.path)")
        }
    }

    // MARK: - Helpers

    private func shortenPath(_ path: String, maxLength: Int = 28) -> String {
        let home = NSHomeDirectory()
        var text = path
        if text.hasPrefix(home) {
            text = "~" + text.dropFirst(home.count)
        }
        if text.count <= maxLength {
            return text
        }
        return "..." + text.suffix(maxLength - 3)
    }

    private func modelDescription(_ modelName: String) -> String {
        let descriptions = [
            "tiny": "Ultrarrápido para borradores cortos. Menos preciso.",
            "base": "Rápido y ligero. Bien para notas internas.",
            "small": "Buen equilibrio para reuniones largas.",
            "medium": "Más preciso, especialmente con audio difícil.",
            "large-v2": "Máxima precisión si priorizas calidad.",
            "large-v3": "Máxima precisión actual para trabajos exigentes."
        ]
        let desc = descriptions[modelName] ?? ""
        return desc
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, subtitle: subtitle)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 12)
    }
}

private struct FormatToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(BrandTheme.primaryAccent)
    }
}

private struct QueueStatusBadge: View {
    let status: FileStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(status.rawValue)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .pending:
            return .secondary
        case .converting, .transcribing, .analyzingVideo:
            return .orange
        case .completed:
            return BrandTheme.primaryAccent
        case .error:
            return .red
        case .canceled:
            return .secondary
        }
    }
}
