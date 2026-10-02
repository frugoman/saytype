import AVFoundation

/// Decodes any audio or video file AVFoundation can read to 16 kHz mono Float32 (what the speech models take).
enum AudioDecoder {
    struct DecodeError: LocalizedError {
        let errorDescription: String?
    }

    static func samples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do { tracks = try await asset.loadTracks(withMediaType: .audio) } catch {
            throw DecodeError(errorDescription: "SayType can't read this file. Try an audio or video file (mp3, m4a, wav, mp4, mov…).")
        }
        guard !tracks.isEmpty else {
            throw DecodeError(errorDescription: "This file has no audio track.")
        }
        // Blocking reads; keep them off the cooperative pool.
        return try await Task.detached(priority: .userInitiated) {
            try read(asset: asset, tracks: tracks)
        }.value
    }

    private static func read(asset: AVAsset, tracks: [AVAssetTrack]) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw DecodeError(errorDescription: "This audio format isn't supported.") }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? DecodeError(errorDescription: "Couldn't start reading the file.")
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                               destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
        }
        if reader.status == .failed { throw reader.error ?? DecodeError(errorDescription: "Reading the file failed.") }
        guard !samples.isEmpty else { throw DecodeError(errorDescription: "This file has no audio.") }
        return samples
    }
}
