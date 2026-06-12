import Foundation

public enum MediaKind: String, Codable, Sendable {
    case audio
    case video
}

public struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(start)-\(end)-\(text.hashValue)" }
    public let start: Double
    public let end: Double
    public let text: String
    
    nonisolated public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptResult: Codable, Identifiable, Hashable, Sendable {
    public var id: String { sourcePath }
    public let sourcePath: String
    public let displayName: String
    public let model: String
    public let language: String
    public let detectedLanguage: String
    public let languageProbability: Double
    public let duration: Double
    public let createdAt: Date
    public var segments: [TranscriptSegment]
    public var outputPaths: [String]
    
    public var text: String {
        segments.compactMap { TranscriptTextCleaner.usefulText(from: $0.text) }
            .joined(separator: "\n")
    }
    
    public init(
        sourcePath: String,
        displayName: String,
        model: String,
        language: String,
        detectedLanguage: String,
        languageProbability: Double,
        duration: Double,
        createdAt: Date,
        segments: [TranscriptSegment] = [],
        outputPaths: [String] = []
    ) {
        self.sourcePath = sourcePath
        self.displayName = displayName
        self.model = model
        self.language = language
        self.detectedLanguage = detectedLanguage
        self.languageProbability = languageProbability
        self.duration = duration
        self.createdAt = createdAt
        self.segments = segments
        self.outputPaths = outputPaths
    }
}

public struct MediaRecording: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var originalFilename: String
    public var sourceURL: URL
    public var mediaKind: MediaKind
    public var createdAt: Date
    public var duration: Double
    public var status: FileStatus
    public var transcriptResult: TranscriptResult?

    public var transcriptText: String {
        transcriptResult?.text ?? ""
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        originalFilename: String,
        sourceURL: URL,
        mediaKind: MediaKind,
        createdAt: Date = Date(),
        duration: Double = 0,
        status: FileStatus = .pending,
        transcriptResult: TranscriptResult? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.sourceURL = sourceURL
        self.mediaKind = mediaKind
        self.createdAt = createdAt
        self.duration = duration
        self.status = status
        self.transcriptResult = transcriptResult
    }
}

public enum FileStatus: String, Codable, Sendable {
    case pending = "Pendiente"
    case converting = "Convertiendo..."
    case transcribing = "Transcribiendo..."
    case analyzingVideo = "Video analysis..."
    case completed = "Completado"
    case error = "Error"
    case canceled = "Cancelado"
}

public enum ModelPreparationState: Equatable {
    case missing
    case preparing
    case ready
    case failed(String)
}

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public var filename: String { url.lastPathComponent }
    public var fileSizeString: String {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resources.fileSize {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(fileSize))
            }
        } catch {}
        return "-"
    }
    public var status: FileStatus = .pending
    public var progress: Double = 0.0 // 0.0 to 1.0
    public var duration: Double = 0.0
    
    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }
}
