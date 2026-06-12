import SwiftUI

struct SettingsView: View {
    @Bindable var controller: AppController

    private let models = ["tiny", "base", "small", "medium", "large-v2", "large-v3"]
    private let languages = [
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
        Form {
            Section {
                HStack(spacing: 14) {
                    Label("Transcript Tools", systemImage: "waveform.and.mic")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    StatusPill(
                        title: "Local y privado",
                        systemImage: "lock",
                        tint: .secondary
                    )
                }
                .padding(.vertical, 4)
            }

            Section("Transcripción") {
                Picker("Modelo", selection: $controller.selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(controller.isRunning || controller.isPreparingModel)

                ModelPreparationPanel(controller: controller, compact: true)

                Picker("Idioma", selection: $controller.selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .disabled(controller.isRunning)

                Toggle("Incluir marcas de tiempo en el transcript", isOn: $controller.includeTimestamps)
                Toggle("Filtrar silencios", isOn: $controller.useVAD)
            }

            Section("Guardado") {
                Toggle("Guardar automáticamente al terminar", isOn: $controller.autoSave)

                HStack {
                    Text("Carpeta")
                    Spacer()
                    Text(shortenPath(controller.outputDirectory.path))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Cambiar") {
                        controller.chooseOutputDirectory()
                    }
                    .disabled(controller.isRunning)
                }

                HStack {
                    Toggle("MD", isOn: $controller.outputFormatMD)
                        .onChange(of: controller.outputFormatMD) { controller.ensureOneFormat() }
                    Toggle("TXT", isOn: $controller.outputFormatTXT)
                        .onChange(of: controller.outputFormatTXT) { controller.ensureOneFormat() }
                    Toggle("SRT", isOn: $controller.outputFormatSRT)
                        .onChange(of: controller.outputFormatSRT) { controller.ensureOneFormat() }
                    Toggle("VTT", isOn: $controller.outputFormatVTT)
                        .onChange(of: controller.outputFormatVTT) { controller.ensureOneFormat() }
                }
                .toggleStyle(.checkbox)
                .disabled(controller.isRunning)
            }

        }
        .formStyle(.grouped)
        .padding(22)
        .frame(width: 520)
        .onAppear {
            controller.refreshModelPreparationState()
        }
    }

    private func shortenPath(_ path: String, maxLength: Int = 42) -> String {
        let home = NSHomeDirectory()
        var text = path
        if text.hasPrefix(home) {
            text = "~" + text.dropFirst(home.count)
        }
        guard text.count > maxLength else { return text }
        return "..." + text.suffix(maxLength - 3)
    }
}
