import SwiftUI

struct StatusCardView: View {
    let statusText: String
    let overallProgress: Double
    let fileProgress: Double
    let completedCount: Int
    let totalProcessedDurationString: String
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(
                    title: "Actual",
                    value: statusText,
                    systemImage: isRunning ? "waveform" : "tray",
                    tint: isRunning ? BrandTheme.primaryAccent : .secondary
                )

                MetricTile(
                    title: "Completados",
                    value: "\(completedCount)",
                    systemImage: "checkmark.seal.fill",
                    tint: BrandTheme.primaryAccent
                )

                MetricTile(
                    title: "Duración",
                    value: totalProcessedDurationString,
                    systemImage: "clock.fill",
                    tint: .orange
                )
            }

            ProgressPanel(
                overallProgress: overallProgress,
                fileProgress: fileProgress,
                isRunning: isRunning
            )
        }
        .padding(.horizontal, 16)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 10)
    }
}

private struct ProgressPanel: View {
    let overallProgress: Double
    let fileProgress: Double
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(isRunning ? "Procesando cola" : "Listo para procesar", systemImage: isRunning ? "bolt.horizontal.fill" : "play.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRunning ? BrandTheme.primaryAccent : .secondary)

                Spacer()

                Text("\(Int(overallProgress))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: overallProgress, total: 100)
                .tint(BrandTheme.primaryAccent)

            if isRunning {
                HStack(spacing: 8) {
                    Text("Archivo actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView(value: fileProgress, total: 100)
                        .tint(BrandTheme.secondaryAccent)
                }
            }
        }
        .appPanel(padding: 10)
    }
}
