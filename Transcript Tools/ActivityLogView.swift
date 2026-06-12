import SwiftUI

struct ActivityLogView: View {
    let logs: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Actividad", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(logs.count) eventos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    if logs.isEmpty {
                        ContentUnavailableView(
                            "Sin actividad",
                            systemImage: "clock",
                            description: Text("El historial aparecerá aquí.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        Text(logs.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .background(Color(nsColor: NSColor.textBackgroundColor))
                .onChange(of: logs) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandTheme.border, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
