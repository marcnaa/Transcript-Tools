import Foundation
import AVFoundation

public enum AudioExtractorError: LocalizedError {
    case noAudioTracks
    case failedToInitializeReader(Error?)
    case failedToStartReading
    
    public var errorDescription: String? {
        switch self {
        case .noAudioTracks:
            return "El archivo no contiene ninguna pista de audio."
        case .failedToInitializeReader(let error):
            return "No se pudo iniciar el lector de audio: \(error?.localizedDescription ?? "Error desconocido")"
        case .failedToStartReading:
            return "Error al leer los datos de audio del archivo."
        }
    }
}

public struct AudioExtractor {
    
    /// Extracts 16kHz mono PCM float samples from any media file.
    /// Supports MP3, M4A, WAV, MP4, MOV, MKV, etc.
    public static func extractPCM(from url: URL, progressHandler: ((Double) -> Void)? = nil) async throws -> (samples: [Float], duration: Double) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        // Load audio tracks asynchronously
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw AudioExtractorError.noAudioTracks
        }
        
        let duration = try await asset.load(.duration).seconds
        
        // Define target audio format: 16kHz, Mono, 32-bit Float PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioExtractorError.failedToInitializeReader(error)
        }
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        if reader.canAdd(trackOutput) {
            reader.add(trackOutput)
        } else {
            throw AudioExtractorError.failedToInitializeReader(nil)
        }
        
        guard reader.startReading() else {
            throw AudioExtractorError.failedToStartReading
        }
        
        var samples = [Float]()
        
        // Read sample buffers
        while reader.status == .reading {
            if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)
                    _ = data.withUnsafeMutableBytes { pointer in
                        guard let baseAddress = pointer.baseAddress else { return }
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                    }
                    
                    // Convert Data bytes to Float array
                    let floatSamples = data.withUnsafeBytes { bufferPointer -> [Float] in
                        let floatCount = length / MemoryLayout<Float>.size
                        guard let baseAddress = bufferPointer.baseAddress else { return [] }
                        let typedPointer = baseAddress.assumingMemoryBound(to: Float.self)
                        return Array(UnsafeBufferPointer(start: typedPointer, count: floatCount))
                    }
                    
                    samples.append(contentsOf: floatSamples)
                }
                
                // Track progress
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                if duration > 0 {
                    let pct = min(1.0, presentationTime / duration)
                    progressHandler?(pct)
                }
            } else {
                break
            }
        }
        
        if reader.status == .failed {
            throw AudioExtractorError.failedToStartReading
        }
        
        return (samples, duration)
    }
}
