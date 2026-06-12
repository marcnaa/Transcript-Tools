import SwiftUI

struct TranscriptionTabView: View {
    @Bindable var controller: AppController

    var body: some View {
        outputPanel
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    private var outputPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Transcripción", systemImage: "text.alignleft")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(controller.currentOutputText.count) caracteres")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Group {
                if controller.currentOutputText.isEmpty {
                    ContentUnavailableView(
                        "Sin transcripción",
                        systemImage: "text.badge.plus",
                        description: Text("El resultado aparecerá aquí.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(controller.currentOutputText)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
            .background(Color(nsColor: NSColor.textBackgroundColor))

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button(action: { controller.saveManual() }) {
                    Label("Guardar", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.currentOutputText.isEmpty)

                Button(action: copyToClipboard) {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(controller.currentOutputText.isEmpty)

                Button(action: { controller.clearQueue() }) {
                    Label("Vaciar cola", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isRunning || controller.files.isEmpty)
            }
            .padding(10)
            .background(.bar)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandTheme.border, lineWidth: 1)
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(controller.currentOutputText, forType: .string)
        controller.log("Copiado al portapapeles.")
    }
}
