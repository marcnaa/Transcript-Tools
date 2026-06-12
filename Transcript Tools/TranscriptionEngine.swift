import Foundation
import WhisperKit

public actor TranscriptionEngine {
    private var whisperKit: WhisperKit? = nil
    private var loadedModel: String? = nil
    private var loadedModelFolder: String? = nil
    
    public init() {}
    
    /// Downloads and loads the selected Whisper model as an explicit user-visible step.
    @discardableResult
    public func prepareModel(
        _ modelName: String,
        logCallback: @escaping @Sendable (String) -> Void,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> String {
        if loadedModel == modelName, let loadedModelFolder, whisperKit != nil {
            return loadedModelFolder
        }

        logCallback("Descargando modelo Whisper '\(modelName)'...")
        let modelFolder = try await WhisperKit.download(
            variant: modelName,
            progressCallback: progressCallback
        )

        logCallback("Preparando modelo Whisper '\(modelName)'...")
        try await loadModel(
            modelName,
            modelFolder: modelFolder.path,
            allowDownload: false,
            logCallback: logCallback
        )

        return modelFolder.path
    }

    /// Loads the Whisper model.
    public func loadModel(
        _ modelName: String,
        modelFolder: String? = nil,
        allowDownload: Bool = false,
        logCallback: @escaping @Sendable (String) -> Void
    ) async throws {
        if loadedModel == modelName && whisperKit != nil {
            return
        }
        
        logCallback("Cargando modelo Whisper '\(modelName)'...")
        
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolder,
            verbose: false,
            load: true,
            download: allowDownload
        )
        let kit = try await WhisperKit(config)
        
        self.whisperKit = kit
        self.loadedModel = modelName
        self.loadedModelFolder = modelFolder ?? kit.modelFolder?.path
        
        logCallback("Modelo Whisper '\(modelName)' cargado y listo en Apple Silicon.")
    }
    
    /// Performs speech-to-text transcription.
    public func transcribe(
        samples: [Float],
        languageCode: String?,
        logCallback: @escaping @Sendable (String) -> Void,
        progressCallback: @escaping @Sendable (String) -> Void
    ) async throws -> [TranscriptSegment] {
        guard let whisperKit = whisperKit else {
            throw NSError(domain: "TranscriptionEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "El modelo Whisper no ha sido cargado."])
        }
        
        logCallback("Iniciando decodificación Whisper...")
        
        let language = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldDetectLanguage = language == nil || language == "" || language == "auto"

        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: shouldDetectLanguage ? nil : language,
            temperature: 0.0,
            usePrefillPrompt: true,
            detectLanguage: shouldDetectLanguage,
            skipSpecialTokens: true,
            suppressBlank: true
        )
        
        options.withoutTimestamps = false
        
        let transcriptionResults = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options) { progress in
            if Task.isCancelled {
                return false // Cancel transcription
            }
            progressCallback(TranscriptTextCleaner.clean(progress.text))
            return true
        }
        
        logCallback("Decodificación Whisper completada con éxito. (\(transcriptionResults.count) resultados)")
        
        let segments: [TranscriptSegment] = transcriptionResults.flatMap { $0.segments }.compactMap { segment -> TranscriptSegment? in
            guard let text = TranscriptTextCleaner.usefulText(from: segment.text) else {
                return nil
            }

            return TranscriptSegment(
                start: Double(segment.start),
                end: Double(segment.end),
                text: text
            )
        }
        
        return segments
    }
}
