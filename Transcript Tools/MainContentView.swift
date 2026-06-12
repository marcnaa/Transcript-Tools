import SwiftUI

struct MainContentView: View {
    @Bindable var controller: AppController
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(hardwareStatus: controller.hardwareStatus)

            StatusCardView(
                statusText: controller.statusText,
                overallProgress: controller.overallProgress,
                fileProgress: controller.fileProgress,
                completedCount: controller.completedCount,
                totalProcessedDurationString: controller.formatDuration(controller.totalProcessedDuration),
                isRunning: controller.isRunning
            )
            .padding(.bottom, 10)

            Picker("", selection: $selectedTab) {
                Label("Transcripción", systemImage: "waveform")
                    .tag(0)
                Label("Actividad", systemImage: "list.bullet.rectangle")
                    .tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Group {
                if selectedTab == 0 {
                    TranscriptionTabView(controller: controller)
                } else {
                    ActivityLogView(logs: controller.logs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                Button(action: { controller.openOutputDirectory() }) {
                    Label("Abrir salida", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Spacer()

                StatusPill(
                    title: "\(controller.files.count) en cola",
                    systemImage: "tray.full",
                    tint: BrandTheme.secondaryAccent
                )

                Button(action: { controller.startOrCancel() }) {
                    if controller.isRunning {
                        Label(controller.isCancelRequested ? "Cancelando..." : "Cancelar", systemImage: "xmark.circle.fill")
                            .frame(minWidth: 128)
                    } else {
                        Label("Transcribir cola", systemImage: "play.fill")
                            .frame(minWidth: 142)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(controller.isRunning ? .red : BrandTheme.primaryAccent)
                .disabled(controller.isCancelRequested || (!controller.isRunning && controller.files.isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
