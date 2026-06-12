import Foundation
import SwiftUI
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
public final class AppController {
    private static let initialSetupCompletedKey = "initialSetupCompleted"
    private static let preparedModelFoldersKey = "preparedModelFolders"

    // Library State
    public var recordings: [MediaRecording] = []
    public var selectedRecordingID: UUID?
    public var selectedRecordingIDs: Set<UUID> = [] {
        didSet {
            if selectedRecordingIDs.isEmpty {
                selectedRecordingID = nil
            } else if let selectedRecordingID, selectedRecordingIDs.contains(selectedRecordingID) {
                return
            } else {
                selectedRecordingID = selectedRecordingIDs.first
            }
        }
    }
    public var shouldShowInitialSetup: Bool = false
    public var activeOutputRecordingID: UUID?

    public var selectedRecording: MediaRecording? {
        if let selectedRecordingID,
           let recording = recordings.first(where: { $0.id == selectedRecordingID }) {
            return recording
        }

        if let selectedRecordingID = selectedRecordingIDs.first,
           let recording = recordings.first(where: { $0.id == selectedRecordingID }) {
            return recording
        }

        return recordings.first
    }

    public var selectedRecordings: [MediaRecording] {
        recordings.filter { selectedRecordingIDs.contains($0.id) }
    }

    public var hasProcessableRecordings: Bool {
        files.contains { $0.status == .pending }
    }

    // Queue State
    public var files: [FileItem] = []
    public var results: [TranscriptResult] = []
    public var logs: [String] = []
    
    // UI Progress State
    public var statusText: String = ""
    public var overallProgress: Double = 0.0
    public var fileProgress: Double = 0.0
    public var completedCount: Int = 0
    public var totalProcessedDuration: Double = 0.0
    
    // App Run State
    public var isRunning: Bool = false
    public var isCancelRequested: Bool = false
    public var modelPreparationState: ModelPreparationState = .missing
    public var modelPreparationProgress: Double = 0.0
    public var modelPreparationMessage: String = "Descarga el modelo para continuar."
    
    // Hardware State
    public var hardwareStatus: String = "Local"
    public var recommendedModel: String = "base"
    
    // User Settings Configuration
    public var selectedModel: String = "base" {
        didSet {
            if oldValue != selectedModel {
                refreshModelPreparationState()
            }
        }
    }
    public var selectedLanguage: String = "auto"
    public var includeTimestamps: Bool = true
    public var autoSave: Bool = true
    public var useVAD: Bool = false
    public var outputDirectory: URL
    
    public var outputFormatMD: Bool = true
    public var outputFormatTXT: Bool = false
    public var outputFormatSRT: Bool = false
    public var outputFormatVTT: Bool = false
    
    // Output Text display
    public var currentOutputText: String = ""
    
    // Engines
    private let transcriptionEngine = TranscriptionEngine()
    private var transcriptionTask: Task<Void, Never>? = nil
    private var modelPreparationTask: Task<Void, Never>? = nil
    private var preparedModelFolders: [String: String] = [:]

    public var isPreparingModel: Bool {
        if case .preparing = modelPreparationState {
            return true
        }
        return false
    }

    public var isSelectedModelReady: Bool {
        guard let path = preparedModelFolders[selectedModel] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    public var canStartTranscription: Bool {
        isRunning || (hasProcessableRecordings && isSelectedModelReady)
    }

    private var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Transcript Tools", isDirectory: true)
    }

    private var recordingsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    private var recordingsIndexURL: URL {
        appSupportDirectory.appendingPathComponent("recordings.json")
    }
    
    public init() {
        // Default output directory is ~/Documents/Transcripciones
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.outputDirectory = documentsURL.appendingPathComponent("Transcripciones")
        } else {
            self.outputDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Transcripciones")
        }
        
        loadPreparedModelFolders()
        loadRecordings()
        rebuildQueueFromRecordings()
        shouldShowInitialSetup = !UserDefaults.standard.bool(forKey: Self.initialSetupCompletedKey)
        refreshModelPreparationState()

        if selectedRecordingID == nil {
            selectedRecordingID = recordings.first?.id
        }

        if let selectedRecordingID {
            selectedRecordingIDs = [selectedRecordingID]
        }
    }
    
    // MARK: - Hardware Detection
    
    public func detectHardware() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        
        var rec = "base"
        
        if ramGB < 4.0 {
            rec = "tiny"
        } else if ramGB < 8.0 {
            rec = "base"
        } else if ramGB < 16.0 {
            rec = "small"
        } else {
            rec = "medium"
        }
        
        self.hardwareStatus = "Local"
        self.recommendedModel = rec
        log("Procesamiento local listo.")
    }

    public func completeInitialSetup() {
        guard isSelectedModelReady else {
            modelPreparationMessage = "Descarga y prepara el modelo antes de empezar."
            return
        }

        ensureOneFormat()
        UserDefaults.standard.set(true, forKey: Self.initialSetupCompletedKey)
        shouldShowInitialSetup = false
        log("Configuración inicial guardada.")
        processPendingRecordings()
    }

    public func prepareSelectedModel() {
        guard !isRunning, !isPreparingModel else { return }

        let modelName = selectedModel
        modelPreparationTask?.cancel()
        modelPreparationState = .preparing
        modelPreparationProgress = 0.0
        modelPreparationMessage = "Descargando \(modelName)..."
        log("Preparación explícita del modelo \(modelName) iniciada.")

        let engine = transcriptionEngine
        modelPreparationTask = Task { [weak self] in
            do {
                let folderPath = try await engine.prepareModel(
                    modelName,
                    logCallback: { @Sendable [weak self] message in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.log(message)
                            if self.selectedModel == modelName {
                                self.modelPreparationMessage = message
                            }
                        }
                    },
                    progressCallback: { @Sendable [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.selectedModel == modelName else { return }
                            let rawPercent = progress.fractionCompleted
                            let percent = rawPercent.isFinite ? max(0, min(1, rawPercent)) : 0
                            self.modelPreparationProgress = percent
                            self.modelPreparationMessage = "Descargando \(modelName) \(Int(percent * 100))%"
                        }
                    }
                )

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.preparedModelFolders[modelName] = folderPath
                    self.persistPreparedModelFolders()

                    if self.selectedModel == modelName {
                        self.modelPreparationState = .ready
                        self.modelPreparationProgress = 1.0
                        self.modelPreparationMessage = "Modelo \(modelName) listo."
                    }

                    self.log("Modelo \(modelName) preparado en: \(folderPath)")
                    self.processPendingRecordings()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.selectedModel == modelName {
                        self.modelPreparationState = .failed(error.localizedDescription)
                        self.modelPreparationProgress = 0.0
                        self.modelPreparationMessage = "No se pudo preparar \(modelName)."
                    }
                    self.log("Error preparando modelo \(modelName): \(error.localizedDescription)")
                }
            }
        }
    }

    public func refreshModelPreparationState() {
        guard !isPreparingModel else { return }

        if let path = preparedModelFolders[selectedModel], FileManager.default.fileExists(atPath: path) {
            modelPreparationState = .ready
            modelPreparationProgress = 1.0
            modelPreparationMessage = "Modelo \(selectedModel) listo."
        } else {
            if preparedModelFolders[selectedModel] != nil {
                preparedModelFolders.removeValue(forKey: selectedModel)
                persistPreparedModelFolders()
            }
            modelPreparationState = .missing
            modelPreparationProgress = 0.0
            modelPreparationMessage = "Descarga \(selectedModel) para continuar."
        }
    }
    
    // MARK: - Queue Management

    public func chooseAndImportFiles() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = Self.supportedMediaTypes

        if openPanel.runModal() == .OK {
            addFiles(urls: openPanel.urls)
        }
    }

    public func chooseOutputDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Carpeta de salida"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            outputDirectory = url
            log("Carpeta de salida cambiada a: \(url.path)")
        }
    }
    
    public func addFiles(urls: [URL]) {
        if !isRunning {
            currentOutputText = ""
            activeOutputRecordingID = nil
        }

        var addedCount = 0
        for url in urls {
            do {
                let recording = try importRecording(from: url)
                recordings.insert(recording, at: 0)
                files.append(FileItem(id: recording.id, url: recording.sourceURL))
                selectedRecordingID = recording.id
                selectedRecordingIDs = [recording.id]
                addedCount += 1
            } catch {
                log("No se pudo importar \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if addedCount > 0 {
            persistRecordings()
            log("Importados \(addedCount) archivos a la biblioteca.")
            self.statusText = addedCount == 1 ? "Procesando nueva grabación" : "Procesando nuevas grabaciones"
            processPendingRecordings()
        }
    }

    public func processPendingRecordings() {
        guard !isRunning, !shouldShowInitialSetup, hasProcessableRecordings else { return }
        guard isSelectedModelReady else {
            statusText = "Prepara el modelo en Ajustes"
            return
        }

        transcriptionTask = Task {
            await runQueue()
        }
    }
    
    public func removeSelectedFiles(items: [FileItem]) {
        guard !isRunning else { return }
        files.removeAll(where: { item in items.contains(where: { $0.id == item.id }) })
        log("Archivos quitados de la cola.")
        updateOverallStatus()
    }
    
    public func clearQueue() {
        guard !isRunning else { return }
        files.removeAll(where: { $0.status == .completed || $0.status == .canceled || $0.status == .error })
        results.removeAll()
        completedCount = 0
        totalProcessedDuration = 0.0
        overallProgress = 0.0
        fileProgress = 0.0
        activeOutputRecordingID = nil
        statusText = files.isEmpty ? "Biblioteca lista" : "Cola lista"
        currentOutputText = ""
        log("Cola de procesamiento limpiada.")
    }

    public func deleteRecording(_ recording: MediaRecording) {
        deleteRecordings(ids: [recording.id])
    }

    public func deleteRecordings(ids: Set<UUID>) {
        guard !isRunning else { return }
        let recordingsToDelete = recordings.filter { ids.contains($0.id) }
        guard !recordingsToDelete.isEmpty else { return }

        let deletedSourcePaths = Set(recordingsToDelete.map { $0.sourceURL.path })
        recordings.removeAll { ids.contains($0.id) }
        files.removeAll { ids.contains($0.id) }
        results.removeAll { deletedSourcePaths.contains($0.sourcePath) }

        for recording in recordingsToDelete {
            let recordingFolder = recordingsDirectory.appendingPathComponent(recording.id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: recordingFolder)
        }

        let remainingIDs = Set(recordings.map(\.id))
        selectedRecordingIDs = selectedRecordingIDs.subtracting(ids).intersection(remainingIDs)

        if let selectedRecordingID, !remainingIDs.contains(selectedRecordingID) {
            self.selectedRecordingID = selectedRecordingIDs.first ?? recordings.first?.id
        }

        if selectedRecordingIDs.isEmpty, let nextID = selectedRecordingID ?? recordings.first?.id {
            selectedRecordingID = nextID
            selectedRecordingIDs = [nextID]
        }

        persistRecordings()
        updateOverallStatus()

        if recordingsToDelete.count == 1, let recording = recordingsToDelete.first {
            log("Grabación eliminada: \(recording.displayName)")
        } else {
            log("\(recordingsToDelete.count) grabaciones eliminadas.")
        }
    }

    public func renameRecording(_ recording: MediaRecording, to proposedName: String) {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let recordingIndex = recordings.firstIndex(where: { $0.id == recording.id }) else { return }

        let oldName = recordings[recordingIndex].displayName
        guard oldName != trimmedName else { return }

        var updatedRecording = recordings[recordingIndex]
        updatedRecording.displayName = trimmedName

        if var result = updatedRecording.transcriptResult {
            let oldMarkdownCandidates = markdownCandidates(for: result, oldDisplayName: oldName)
            let newMarkdownURL = outputDirectory.appendingPathComponent("\(safeOutputName(trimmedName))_transcripcion.md")

            for oldURL in oldMarkdownCandidates where FileManager.default.fileExists(atPath: oldURL.path) {
                do {
                    try FileManager.default.createDirectory(at: newMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: newMarkdownURL.path) {
                        try FileManager.default.removeItem(at: newMarkdownURL)
                    }
                    try FileManager.default.moveItem(at: oldURL, to: newMarkdownURL)
                    result.outputPaths.removeAll { $0 == oldURL.path }
                    result.outputPaths.append(newMarkdownURL.path)
                    log("Markdown renombrado: \(newMarkdownURL.lastPathComponent)")
                    break
                } catch {
                    log("No se pudo renombrar el Markdown: \(error.localizedDescription)")
                }
            }

            updatedRecording.transcriptResult = result

            if let resultIndex = results.firstIndex(where: { $0.sourcePath == result.sourcePath }) {
                results[resultIndex] = result
            }
        }

        recordings[recordingIndex] = updatedRecording
        persistRecordings()
        log("Grabación renombrada: \(oldName) → \(trimmedName)")
    }

    private static var supportedMediaTypes: [UTType] {
        [
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
    }

    // MARK: - Library Persistence

    private func loadPreparedModelFolders() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.preparedModelFoldersKey) as? [String: String] else {
            return
        }

        preparedModelFolders = stored.filter { _, path in
            FileManager.default.fileExists(atPath: path)
        }

        if preparedModelFolders.count != stored.count {
            persistPreparedModelFolders()
        }
    }

    private func persistPreparedModelFolders() {
        UserDefaults.standard.set(preparedModelFolders, forKey: Self.preparedModelFoldersKey)
    }

    private func importRecording(from sourceURL: URL) throws -> MediaRecording {
        let id = UUID()
        let recordingFolder = recordingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        let destinationURL = recordingFolder.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return MediaRecording(
            id: id,
            displayName: sourceURL.deletingPathExtension().lastPathComponent,
            originalFilename: filename,
            sourceURL: destinationURL,
            mediaKind: mediaKind(for: sourceURL),
            status: .pending
        )
    }

    private func loadRecordings() {
        guard FileManager.default.fileExists(atPath: recordingsIndexURL.path) else { return }

        do {
            let data = try Data(contentsOf: recordingsIndexURL)
            let decoded = try JSONDecoder().decode([MediaRecording].self, from: data)
            recordings = decoded
                .map { recording in
                    var normalized = recording
                    switch normalized.status {
                    case .converting, .transcribing, .analyzingVideo:
                        normalized.status = .pending
                    case .pending, .completed, .error, .canceled:
                        break
                    }
                    return normalized
                }
                .filter { FileManager.default.fileExists(atPath: $0.sourceURL.path) }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            log("No se pudo cargar la biblioteca: \(error.localizedDescription)")
        }
    }

    private func persistRecordings() {
        do {
            try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recordings)
            try data.write(to: recordingsIndexURL, options: .atomic)
        } catch {
            log("No se pudo guardar la biblioteca: \(error.localizedDescription)")
        }
    }

    private func rebuildQueueFromRecordings() {
        files = recordings
            .filter { $0.status != .completed }
            .map { recording in
                var item = FileItem(id: recording.id, url: recording.sourceURL)
                item.status = recording.status
                item.duration = recording.duration
                return item
            }
    }

    private func mediaKind(for url: URL) -> MediaKind {
        isVideoFile(url) ? .video : .audio
    }
    
    // MARK: - Logging
    
    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
    }
    
    // MARK: - Format Checking
    
    public func ensureOneFormat() {
        if !outputFormatMD && !outputFormatTXT && !outputFormatSRT && !outputFormatVTT {
            outputFormatMD = true
        }
    }
    
    // MARK: - Transcription Process
    
    public func startOrCancel() {
        if isRunning {
            requestCancel()
        } else {
            guard isSelectedModelReady else {
                statusText = "Prepara el modelo en Ajustes"
                log("Transcripción bloqueada: el modelo \(selectedModel) no está preparado.")
                return
            }

            transcriptionTask = Task {
                await runQueue()
            }
        }
    }
    
    private func requestCancel() {
        transcriptionTask?.cancel()
        isCancelRequested = true
        statusText = "Cancelando..."
        log("Cancelación solicitada por el usuario.")
    }
    
    private func runQueue() async {
        guard hasProcessableRecordings else {
            statusText = recordings.isEmpty ? "" : "Todo transcrito"
            return
        }

        guard let preparedModelFolder = preparedModelFolders[selectedModel],
              FileManager.default.fileExists(atPath: preparedModelFolder) else {
            refreshModelPreparationState()
            statusText = "Prepara el modelo en Ajustes"
            log("Transcripción bloqueada: el modelo \(selectedModel) no está preparado.")
            return
        }
        
        ensureOneFormat()
        
        isRunning = true
        isCancelRequested = false
        results.removeAll()
        completedCount = 0
        totalProcessedDuration = 0.0
        overallProgress = 0.0
        fileProgress = 0.0
        currentOutputText = ""
        activeOutputRecordingID = nil
        
        log("========================================================")
        log("Iniciando procesamiento de cola. Modelo: \(selectedModel) · Idioma: \(selectedLanguage)")
        
        do {
            // Load Whisper Model
            try await transcriptionEngine.loadModel(selectedModel, modelFolder: preparedModelFolder, allowDownload: false, logCallback: { @Sendable [weak self] logMsg in
                guard let self = self else { return }
                Task { @MainActor in self.log(logMsg) }
            })
        } catch {
            log("Error al cargar el modelo Whisper: \(error.localizedDescription)")
            statusText = "No se pudo cargar el modelo"
            modelPreparationState = .failed("No se pudo cargar el modelo preparado.")
            modelPreparationMessage = "Vuelve a prepararlo desde Ajustes."
            modelPreparationProgress = 0.0
            isRunning = false
            return
        }
        
        while let file = files.first(where: { $0.status == .pending }) {
            let index = completedCount
            let totalFiles = max(1, completedCount + files.filter { $0.status == .pending }.count)
            let displayName = recordings.first(where: { $0.id == file.id })?.displayName
                ?? file.url.deletingPathExtension().lastPathComponent

            if isCancelRequested || Task.isCancelled {
                updateFileStatus(id: file.id, status: .canceled, progress: 0.0)
                break
            }
            
            // Mark Active
            updateFileStatus(id: file.id, status: .converting, progress: 0.0)
            selectedRecordingID = file.id
            selectedRecordingIDs = [file.id]
            activeOutputRecordingID = file.id
            self.statusText = "Procesando \(displayName)..."
            log("----------------------------------------")
            log("[\(index + 1)/\(totalFiles)] Iniciando \(displayName)")
            
            currentOutputText = "# \(displayName)\n\n"
            
            // Step 1: Convert/Extract Audio PCM
            var pcmData: [Float] = []
            var duration: Double = 0.0
            do {
                let result = try await AudioExtractor.extractPCM(from: file.url) { [weak self] prog in
                    Task { @MainActor in
                        self?.fileProgress = prog * 100.0
                        self?.overallProgress = ((Double(index) + (prog * 0.1)) / Double(totalFiles)) * 100.0
                        self?.updateFileProgress(id: file.id, progress: prog * 0.1)
                    }
                }
                pcmData = result.samples
                duration = result.duration
                updateFileStatus(id: file.id, status: .transcribing, progress: 0.1)
                updateRecordingDuration(id: file.id, duration: duration)
                log("Audio extraído con éxito. Duración: \(formatDuration(duration))")
            } catch {
                log("Error en extracción de audio: \(error.localizedDescription)")
                updateFileStatus(id: file.id, status: .error, progress: 0.0)
                persistRecordings()
                continue
            }
            
            // Step 2: Transcribe via WhisperKit
            var segments: [TranscriptSegment] = []
            do {
                segments = try await transcriptionEngine.transcribe(
                    samples: pcmData,
                    languageCode: selectedLanguage,
                    logCallback: { @Sendable [weak self] msg in
                        guard let self = self else { return }
                        Task { @MainActor in self.log(msg) }
                    },
                    progressCallback: { @Sendable [weak self] liveText in
                        guard let self = self else { return }
                        Task { @MainActor in
                            let preview = liveText.count > 40 ? "..." + liveText.suffix(40) : liveText
                            self.statusText = "Transcribiendo: \(preview)"
                        }
                    }
                )
                
                // Print segments as they arrive or update output UI
                for segment in segments {
                    await appendLiveSegment(segment)
                }
            } catch {
                log("Error de transcripción o cancelado: \(error.localizedDescription)")
                updateFileStatus(id: file.id, status: .error, progress: 0.1)
                persistRecordings()
                continue
            }
            
            if isCancelRequested {
                updateFileStatus(id: file.id, status: .canceled, progress: 0.0)
                break
            }
            
            var transcriptResult = TranscriptResult(
                sourcePath: file.url.path,
                displayName: displayName,
                model: selectedModel,
                language: selectedLanguage,
                detectedLanguage: selectedLanguage, // Default, updated on Whisper completion if possible
                languageProbability: 1.0,
                duration: duration,
                createdAt: Date(),
                segments: segments
            )
            
            if autoSave {
                do {
                    let savedPaths = try writeResultFiles(transcriptResult)
                    transcriptResult.outputPaths = savedPaths.map(\.path)
                    log("Guardado automático: \(savedPaths.map { $0.lastPathComponent }.joined(separator: ", "))")
                } catch {
                    log("Error de guardado automático: \(error.localizedDescription)")
                }
            }

            // Save Results
            results.append(transcriptResult)
            completedCount += 1
            totalProcessedDuration += duration
            
            updateFileStatus(id: file.id, status: .completed, progress: 1.0)
            completeRecording(id: file.id, result: transcriptResult)
            overallProgress = (Double(index + 1) / Double(totalFiles)) * 100.0
            fileProgress = 100.0
        }
        
        if isCancelRequested || Task.isCancelled {
            statusText = "Cancelado"
            log("Cancelado por el usuario")
        } else {
            statusText = "Todo transcrito"
            log("Procesamiento completado")
        }
        
        isRunning = false
        persistRecordings()
    }
    
    // MARK: - Save Handlers
    
    public func saveManual() {
        guard !results.isEmpty else {
            // Manual save of the current text window if results is empty
            let content = currentOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            
            let savePanel = NSSavePanel()
            let markdownType = UTType(filenameExtension: "md") ?? .plainText
            savePanel.allowedContentTypes = [markdownType, .plainText]
            savePanel.nameFieldStringValue = "transcripcion.md"
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
                log("Guardado manual en: \(url.path)")
            }
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Selecciona la carpeta donde guardar los archivos"
        
        if openPanel.runModal() == .OK, let folder = openPanel.url {
            do {
                var count = 0
                for result in results {
                    let written = try writeResultFiles(result, toDirectory: folder)
                    count += written.count
                }
                log("Guardado manual: \(count) archivos guardados en \(folder.lastPathComponent)")
            } catch {
                log("Error al guardar archivos manualmente: \(error.localizedDescription)")
            }
        }
    }
    
    public func openOutputDirectory() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDirectory.path)
    }

    public func exportTranscript(for recording: MediaRecording) {
        guard let result = recording.transcriptResult else { return }

        let savePanel = NSSavePanel()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        savePanel.allowedContentTypes = [markdownType]
        savePanel.nameFieldStringValue = "\(safeOutputName(recording.displayName))_transcripcion.md"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let content = buildMarkdown(result, includeTimestamps: includeTimestamps)
                try content.write(to: url, atomically: true, encoding: .utf8)
                log("Transcript exportado: \(url.path)")
            } catch {
                log("No se pudo exportar el transcript: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - File Writing
    
    @discardableResult
    private func writeResultFiles(_ result: TranscriptResult, toDirectory folder: URL? = nil) throws -> [URL] {
        let dir = folder ?? outputDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let cleanedBase = safeOutputName(result.displayName)
        var saved = [URL]()
        
        if outputFormatMD {
            let mdContent = buildMarkdown(result, includeTimestamps: includeTimestamps)
            let fileURL = dir.appendingPathComponent("\(cleanedBase)_transcripcion.md")
            try mdContent.write(to: fileURL, atomically: true, encoding: .utf8)
            saved.append(fileURL)
        }
        if outputFormatTXT {
            let txtContent = buildTxt(result, includeTimestamps: includeTimestamps)
            let fileURL = dir.appendingPathComponent("\(cleanedBase)_transcripcion.txt")
            try txtContent.write(to: fileURL, atomically: true, encoding: .utf8)
            saved.append(fileURL)
        }
        if outputFormatSRT {
            let srtContent = buildSRT(result)
            let fileURL = dir.appendingPathComponent("\(cleanedBase)_transcripcion.srt")
            try srtContent.write(to: fileURL, atomically: true, encoding: .utf8)
            saved.append(fileURL)
        }
        if outputFormatVTT {
            let vttContent = buildVTT(result)
            let fileURL = dir.appendingPathComponent("\(cleanedBase)_transcripcion.vtt")
            try vttContent.write(to: fileURL, atomically: true, encoding: .utf8)
            saved.append(fileURL)
        }
        return saved
    }
    
    // MARK: - Helpers
    
    private func updateFileStatus(id: UUID, status: FileStatus, progress: Double) {
        if let idx = files.firstIndex(where: { $0.id == id }) {
            files[idx].status = status
            files[idx].progress = progress
        }

        if let recordingIndex = recordings.firstIndex(where: { $0.id == id }) {
            recordings[recordingIndex].status = status
        }
    }
    
    private func updateFileProgress(id: UUID, progress: Double) {
        if let idx = files.firstIndex(where: { $0.id == id }) {
            files[idx].progress = progress
        }
    }

    private func updateRecordingDuration(id: UUID, duration: Double) {
        if let recordingIndex = recordings.firstIndex(where: { $0.id == id }) {
            recordings[recordingIndex].duration = duration
        }
    }

    private func completeRecording(id: UUID, result: TranscriptResult) {
        if let recordingIndex = recordings.firstIndex(where: { $0.id == id }) {
            recordings[recordingIndex].status = .completed
            recordings[recordingIndex].duration = result.duration
            recordings[recordingIndex].transcriptResult = result
            selectedRecordingID = id
            selectedRecordingIDs = [id]
        }
    }
    
    private func updateOverallStatus() {
        if recordings.isEmpty {
            statusText = "Importa audio o video"
        } else if files.isEmpty {
            statusText = "Biblioteca lista"
        } else {
            statusText = "Cola lista"
        }
    }
    
    private func appendLiveSegment(_ segment: TranscriptSegment) async {
        guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { return }

        await MainActor.run {
            if self.includeTimestamps {
                self.currentOutputText += "[\(self.formatClock(segment.start))] \(text)\n"
            } else {
                self.currentOutputText += text + "\n"
            }
        }
    }
    
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "webm", "ts"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
    
    private func safeOutputName(_ value: String) -> String {
        let filename = value.contains("/")
            ? URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
            : value
        let cleaned = filename.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted).joined()
        let noSpaces = cleaned.replacingOccurrences(of: " ", with: "_")
        return noSpaces.isEmpty ? "transcripcion" : noSpaces
    }

    private func markdownCandidates(for result: TranscriptResult, oldDisplayName: String) -> [URL] {
        var candidates = result.outputPaths
            .filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "md" }
            .map { URL(fileURLWithPath: $0) }

        candidates.append(outputDirectory.appendingPathComponent("\(safeOutputName(result.sourcePath))_transcripcion.md"))
        candidates.append(outputDirectory.appendingPathComponent("\(safeOutputName(oldDisplayName))_transcripcion.md"))

        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
    
    // MARK: - Clock Formatters
    
    public func formatClock(_ seconds: Double, decimal: String = ".", forceHours: Bool = false) -> String {
        let totalMs = Int(round(seconds * 1000.0))
        let hours = totalMs / 3_600_000
        var remainder = totalMs % 3_600_000
        let minutes = remainder / 60_000
        remainder = remainder % 60_000
        let secs = remainder / 1000
        let millis = remainder % 1000
        
        if forceHours || hours > 0 {
            return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, decimal, millis)
        } else {
            return String(format: "%02d:%02d%@%03d", minutes, secs, decimal, millis)
        }
    }
    
    public func formatDuration(_ seconds: Double) -> String {
        let secs = Int(seconds)
        let minutes = secs / 60
        let remainingSecs = secs % 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours) h \(remainingMinutes) min"
        } else if remainingMinutes > 0 {
            return "\(remainingMinutes) min \(remainingSecs) s"
        } else {
            return "\(remainingSecs) s"
        }
    }
    
    // MARK: - Document Builders
    
    private func buildMarkdown(_ result: TranscriptResult, includeTimestamps: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let created = formatter.string(from: result.createdAt)
        
        var lines = [
            "# Transcripción: \(result.displayName)",
            "",
            "- Generado: \(created)",
            "- Modelo: \(result.model)",
            "- Idioma: \(result.language)",
            "- Duración: \(formatDuration(result.duration))",
            "",
            "---",
            ""
        ]
        
        if includeTimestamps {
            for segment in result.segments {
                guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { continue }
                lines.append("**[\(formatClock(segment.start))]** \(text)")
                lines.append("")
            }
        } else {
            lines.append(result.text)
            lines.append("")
        }
        
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    
    private func buildTxt(_ result: TranscriptResult, includeTimestamps: Bool) -> String {
        var transcript = ""
        if includeTimestamps {
            transcript = result.segments.compactMap { segment in
                guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { return nil }
                return "[\(formatClock(segment.start))] \(text)"
            }.joined(separator: "\n")
        } else {
            transcript = result.text
        }
        
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    
    private func buildSRT(_ result: TranscriptResult) -> String {
        var chunks = [String]()
        var index = 1
        for segment in result.segments {
            guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { continue }
            chunks.append("\(index)")
            chunks.append("\(formatClock(segment.start, decimal: ",", forceHours: true)) --> \(formatClock(segment.end, decimal: ",", forceHours: true))")
            chunks.append(text)
            chunks.append("")
            index += 1
        }
        return chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    
    private func buildVTT(_ result: TranscriptResult) -> String {
        var chunks = ["WEBVTT", ""]
        for segment in result.segments {
            guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else { continue }
            chunks.append("\(formatClock(segment.start, forceHours: true)) --> \(formatClock(segment.end, forceHours: true))")
            chunks.append(text)
            chunks.append("")
        }
        return chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
