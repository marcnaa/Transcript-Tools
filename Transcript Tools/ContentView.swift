import SwiftUI

struct ContentView: View {
    @Bindable var controller: AppController
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isRecordingStudioPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RecordingsSidebarView(
                controller: controller,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 380)
        } detail: {
            Group {
                if let recording = controller.selectedRecording {
                    RecordingDetailView(controller: controller, recording: recording)
                        .id(recording.id)
                } else {
                    EmptyLibraryView(importAction: controller.chooseAndImportFiles)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandTheme.contentBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Buscar grabaciones")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: controller.chooseAndImportFiles) {
                    Label("Importar", systemImage: "plus")
                }
                .glassControl()
                .help("Importar audio o video")

                Button {
                    isRecordingStudioPresented = true
                } label: {
                    Label("Grabar", systemImage: "waveform")
                }
                .glassControl()
                .help("Grabar desde el micrófono o el audio del Mac")

                Button(action: { controller.startOrCancel() }) {
                    Label(
                        controller.isRunning ? "Cancelar" : "Transcribir",
                        systemImage: controller.isRunning ? "xmark.circle.fill" : "play.fill"
                    )
                }
                .glassProminentControl()
                .tint(controller.isRunning ? .red : BrandTheme.primaryAccent)
                .disabled(!controller.isRunning && !controller.canStartTranscription)
                .help(transcribeHelp)

                SettingsLink {
                    Label("Ajustes", systemImage: "gearshape")
                }
                .glassControl()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $controller.shouldShowInitialSetup) {
            InitialSetupView(controller: controller)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isRecordingStudioPresented) {
            RecordingStudioView(controller: controller)
        }
        .onAppear {
            controller.detectHardware()
            controller.refreshModelPreparationState()
            controller.processPendingRecordings()
        }
    }

    private var transcribeHelp: String {
        if controller.isRunning {
            return "Cancelar transcripción"
        }

        if !controller.isSelectedModelReady {
            return "Prepara el modelo en Ajustes para transcribir"
        }

        return "Transcribir grabaciones pendientes"
    }
}

private struct EmptyLibraryView: View {
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(BrandTheme.primaryAccent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Transcript Tools")
                    .font(.title2.weight(.semibold))

                Text("Tu biblioteca de transcripciones")
                    .font(.headline)

                Text("Importa audio o video. La app lo guardará localmente con su reproductor y transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: importAction) {
                Label("Importar archivo", systemImage: "plus")
            }
            .controlSize(.large)
            .glassProminentControl()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    ContentView(controller: AppController())
}
