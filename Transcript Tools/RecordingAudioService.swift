import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Observation
@preconcurrency import ScreenCaptureKit

enum RecordingSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            return "Micrófono"
        case .systemAudio:
            return "Reunión"
        }
    }

    var iconName: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .systemAudio:
            return "person.2.wave.2"
        }
    }

    var idleMessage: String {
        switch self {
        case .microphone:
            return "Lista para grabar desde el micrófono."
        case .systemAudio:
            return "Lista para grabar reuniones: audio del Mac y tu micrófono."
        }
    }
}

enum RecordingState: Equatable {
    case idle
    case requestingPermission
    case recording
    case finishing
    case failed(String)
}

@Observable
@MainActor
final class RecordingSessionController {
    var source: RecordingSource = .microphone {
        didSet {
            if !isRecording {
                message = source.idleMessage
            }
        }
    }
    var state: RecordingState = .idle
    var elapsed: TimeInterval = 0
    var message: String = RecordingSource.microphone.idleMessage

    private var microphoneRecorder = MicrophoneAudioRecorder()
    private var meetingRecorder = MeetingAudioRecorder()
    private var timer: Timer?
    private var startDate: Date?

    var isRecording: Bool {
        state == .recording
    }

    var isBusy: Bool {
        state == .requestingPermission || state == .finishing
    }

    var failureMessage: String? {
        if case .failed(let message) = state {
            return message
        }

        return nil
    }

    func start() async {
        guard !isRecording, !isBusy else { return }

        state = .requestingPermission
        message = "Comprobando permisos..."

        do {
            let url = try Self.makeTemporaryURL()

            switch source {
            case .microphone:
                try await microphoneRecorder.start(to: url)
            case .systemAudio:
                try await meetingRecorder.start(to: url)
            }

            startDate = Date()
            elapsed = 0
            state = .recording
            message = source == .systemAudio
                ? "Grabando reunión (Mac + micrófono)..."
                : "Grabando \(source.title.lowercased())..."
            beginTimer()
        } catch {
            stopTimer()
            state = .failed(error.localizedDescription)
            message = "No se pudo empezar a grabar."
        }
    }

    func stop() async throws -> URL? {
        guard isRecording else { return nil }

        state = .finishing
        message = "Guardando grabación..."
        stopTimer()

        do {
            let outputURL: URL?

            switch source {
            case .microphone:
                outputURL = microphoneRecorder.stop()
            case .systemAudio:
                outputURL = try await meetingRecorder.stop()
            }

            elapsed = 0
            startDate = nil
            state = .idle
            message = source.idleMessage
            return outputURL
        } catch {
            state = .failed(error.localizedDescription)
            message = "No se pudo guardar la grabación."
            throw error
        }
    }

    func discardFailure() {
        state = .idle
        message = source.idleMessage
    }

    private func beginTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func makeTemporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Transcript Tools Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
    }
}

nonisolated final class MicrophoneAudioRecorder {
    private var recorder: AVAudioRecorder?

    func start(to url: URL) async throws {
        guard await Self.requestPermission() else {
            throw RecordingServiceError.permissionDenied("Permiso de micrófono denegado.")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecordingServiceError.startFailed("No se pudo iniciar el micrófono.")
        }

        self.recorder = recorder
    }

    func stop() -> URL? {
        guard let recorder else { return nil }

        recorder.stop()
        self.recorder = nil
        return recorder.url
    }

    private static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

/// Records system audio and microphone together for meetings (others on the call + your voice).
nonisolated final class MeetingAudioRecorder {
    private let systemRecorder = SystemAudioRecorder()
    private let microphoneRecorder = MicrophoneAudioRecorder()
    private var finalURL: URL?
    private var systemURL: URL?
    private var microphoneURL: URL?

    func start(to url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        let systemURL = directory.appendingPathComponent("system-\(UUID().uuidString).m4a")
        let microphoneURL = directory.appendingPathComponent("mic-\(UUID().uuidString).m4a")

        finalURL = url
        self.systemURL = systemURL
        self.microphoneURL = microphoneURL

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.microphoneRecorder.start(to: microphoneURL)
                }
                group.addTask {
                    try await self.systemRecorder.start(to: systemURL)
                }
                try await group.waitForAll()
            }
        } catch {
            try? FileManager.default.removeItem(at: systemURL)
            try? FileManager.default.removeItem(at: microphoneURL)
            reset()
            throw error
        }
    }

    func stop() async throws -> URL? {
        guard let finalURL, let systemURL, let microphoneURL else { return nil }

        defer {
            try? FileManager.default.removeItem(at: systemURL)
            try? FileManager.default.removeItem(at: microphoneURL)
            reset()
        }

        let capturedSystemURL = try await systemRecorder.stop()
        let capturedMicrophoneURL = microphoneRecorder.stop()

        guard let capturedSystemURL, let capturedMicrophoneURL else {
            throw RecordingServiceError.emptyRecording
        }

        try await AudioMerger.merge(
            systemURL: capturedSystemURL,
            microphoneURL: capturedMicrophoneURL,
            outputURL: finalURL
        )

        return finalURL
    }

    private func reset() {
        finalURL = nil
        systemURL = nil
        microphoneURL = nil
    }
}

nonisolated enum AudioMerger {
    static func merge(systemURL: URL, microphoneURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let systemAsset = AVURLAsset(url: systemURL)
        let microphoneAsset = AVURLAsset(url: microphoneURL)

        let systemTracks = try await systemAsset.loadTracks(withMediaType: .audio)
        let microphoneTracks = try await microphoneAsset.loadTracks(withMediaType: .audio)

        guard let systemTrack = systemTracks.first, let microphoneTrack = microphoneTracks.first else {
            throw RecordingServiceError.emptyRecording
        }

        let systemDuration = try await systemAsset.load(.duration)
        let microphoneDuration = try await microphoneAsset.load(.duration)
        let mixDuration = CMTimeMinimum(systemDuration, microphoneDuration)

        guard mixDuration.seconds > 0 else {
            throw RecordingServiceError.emptyRecording
        }

        guard
            let compositionSystemTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let compositionMicrophoneTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw RecordingServiceError.startFailed("No se pudo preparar la mezcla de audio.")
        }

        let timeRange = CMTimeRange(start: .zero, duration: mixDuration)
        try compositionSystemTrack.insertTimeRange(timeRange, of: systemTrack, at: .zero)
        try compositionMicrophoneTrack.insertTimeRange(timeRange, of: microphoneTrack, at: .zero)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingServiceError.finishFailed
        }

        try await exportSession.export(to: outputURL, as: .m4a)
    }
}

nonisolated final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let sampleQueue = DispatchQueue(label: "transcript-tools.system-audio-recorder.samples")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var didStartSession = false
    private var streamError: Error?

    func start(to url: URL) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw RecordingServiceError.permissionDenied("Permiso de grabación de pantalla denegado.")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw RecordingServiceError.startFailed("No se encontró ninguna pantalla para capturar audio.")
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingServiceError.startFailed("No se pudo preparar el archivo de audio.")
        }

        writer.add(input)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

            self.stream = stream
            self.writer = writer
            self.writerInput = input
            self.outputURL = url
            self.didStartSession = false
            self.streamError = nil

            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            reset()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() async throws -> URL? {
        guard let writer else { return nil }

        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        }

        sampleQueue.sync {}

        if let streamError {
            reset()
            throw streamError
        }

        guard didStartSession, let outputURL else {
            writer.cancelWriting()
            let url = self.outputURL
            reset()
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            throw RecordingServiceError.emptyRecording
        }

        writerInput?.markAsFinished()
        try await AssetWriterFinisher(writer: writer).finish()

        reset()
        return outputURL
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let writer,
              let writerInput else {
            return
        }

        if !didStartSession {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            didStartSession = true
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        streamError = error
    }

    private func reset() {
        stream = nil
        writer = nil
        writerInput = nil
        outputURL = nil
        didStartSession = false
        streamError = nil
    }
}

nonisolated private final class AssetWriterFinisher: @unchecked Sendable {
    private let writer: AVAssetWriter

    init(writer: AVAssetWriter) {
        self.writer = writer
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting { [self] in
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? RecordingServiceError.finishFailed)
                }
            }
        }
    }
}

enum RecordingServiceError: LocalizedError {
    case permissionDenied(String)
    case startFailed(String)
    case emptyRecording
    case finishFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return message
        case .startFailed(let message):
            return message
        case .emptyRecording:
            return "No se recibió audio durante la grabación."
        case .finishFailed:
            return "No se pudo cerrar el archivo de audio."
        }
    }
}
