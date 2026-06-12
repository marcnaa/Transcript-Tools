import SwiftUI

struct InitialSetupView: View {
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
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(BrandTheme.primaryAccent)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Transcript Tools")
                        .font(.title2.weight(.semibold))

                    Text("Configura tu flujo")
                        .font(.headline)

                    Text("Puedes cambiarlo después desde Ajustes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Picker("Modelo", selection: $controller.selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(controller.isPreparingModel)

                ModelPreparationPanel(controller: controller)

                Picker("Idioma", selection: $controller.selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                Toggle("Filtrar silencios", isOn: $controller.useVAD)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button {
                    controller.completeInitialSetup()
                } label: {
                    Text("Empezar")
                        .frame(minWidth: 112)
                }
                .controlSize(.large)
                .glassProminentControl()
                .disabled(!controller.isSelectedModelReady || controller.isPreparingModel)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            controller.refreshModelPreparationState()
        }
    }
}

struct ModelPreparationPanel: View {
    @Bindable var controller: AppController
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 16 : 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)

                if controller.isPreparingModel {
                    ProgressView(value: controller.modelPreparationProgress, total: 1)
                        .tint(BrandTheme.primaryAccent)
                }
            }

            Spacer()

            if shouldShowAction {
                Button(action: controller.prepareSelectedModel) {
                    Label(actionTitle, systemImage: "arrow.down.circle")
                }
                .disabled(controller.isRunning || controller.isPreparingModel)
            }
        }
        .padding(.vertical, compact ? 4 : 8)
    }

    private var title: String {
        switch controller.modelPreparationState {
        case .ready:
            return "Modelo preparado"
        case .preparing:
            return "Preparando modelo"
        case .failed:
            return "Preparación fallida"
        case .missing:
            return "Modelo pendiente"
        }
    }

    private var message: String {
        switch controller.modelPreparationState {
        case .failed(let detail):
            return detail.isEmpty ? controller.modelPreparationMessage : detail
        default:
            return controller.modelPreparationMessage
        }
    }

    private var iconName: String {
        switch controller.modelPreparationState {
        case .ready:
            return "checkmark.circle.fill"
        case .preparing:
            return "arrow.down.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .missing:
            return "icloud.and.arrow.down"
        }
    }

    private var tint: Color {
        switch controller.modelPreparationState {
        case .ready:
            return BrandTheme.primaryAccent
        case .preparing:
            return .orange
        case .failed:
            return .red
        case .missing:
            return .secondary
        }
    }

    private var actionTitle: String {
        if case .failed = controller.modelPreparationState {
            return "Reintentar"
        }
        return "Descargar"
    }

    private var shouldShowAction: Bool {
        switch controller.modelPreparationState {
        case .missing, .failed:
            return true
        case .preparing, .ready:
            return false
        }
    }
}
