import SwiftUI

struct HeaderView: View {
    let hardwareStatus: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript Tools")
                    .font(.system(size: 28, weight: .semibold))

                Text("Transcripción local para reuniones, entrevistas y vídeos")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()

            StatusPill(
                title: hardwareStatus,
                systemImage: hardwareSymbol,
                tint: hardwareTint
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var hardwareSymbol: String {
        let normalizedStatus = hardwareStatus.lowercased()

        if normalizedStatus.contains("error") || normalizedStatus.contains("no") {
            return "exclamationmark.triangle.fill"
        }

        return "lock"
    }

    private var hardwareTint: Color {
        let normalizedStatus = hardwareStatus.lowercased()

        if normalizedStatus.contains("error") || normalizedStatus.contains("no") {
            return .orange
        }

        return .secondary
    }
}
