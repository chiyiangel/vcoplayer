import AudioToolbox
import AVFAudio
import Foundation

public struct PlaybackProgress: Codable, Equatable, Sendable {
    public let elapsedSeconds: Double
    public let durationSeconds: Double?

    public init(elapsedSeconds: Double, durationSeconds: Double?) {
        self.elapsedSeconds = elapsedSeconds
        self.durationSeconds = durationSeconds
    }
}

public struct PlaybackStartRequest: Equatable, Sendable {
    public let fileURL: URL
    public let relativePath: String
    public let outputDevice: OutputDevice
    public let resumeAtSeconds: Double?

    public init(fileURL: URL, relativePath: String, outputDevice: OutputDevice, resumeAtSeconds: Double? = nil) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.outputDevice = outputDevice
        self.resumeAtSeconds = resumeAtSeconds
    }
}

public enum PlaybackStartResult: Equatable, Sendable {
    case playing(PlaybackProgress)
    case unsupported(String)
}

public struct PlaybackPauseResult: Equatable, Sendable {
    public let progress: PlaybackProgress

    public init(progress: PlaybackProgress) {
        self.progress = progress
    }
}

public protocol PlaybackControlling: Sendable {
    func start(_ request: PlaybackStartRequest) async -> PlaybackStartResult
    func pause() async -> PlaybackPauseResult
}

public actor CoreAudioPlaybackController: PlaybackControlling {
    private var player: AVAudioPlayer?
    private var durationSeconds: Double?

    public init() {}

    public func start(_ request: PlaybackStartRequest) async -> PlaybackStartResult {
        if let resumeAtSeconds = request.resumeAtSeconds, let player = self.player {
            player.currentTime = resumeAtSeconds
            guard player.play() else {
                return .unsupported("Unsupported Playback: CoreAudio playback path could not resume.")
            }
            return .playing(
                PlaybackProgress(
                    elapsedSeconds: player.currentTime,
                    durationSeconds: self.durationSeconds
                )
            )
        }

        do {
            let inspection = try Self.inspectAudioFile(request.fileURL)
            guard Self.isSupportedLosslessSource(fileURL: request.fileURL, formatID: inspection.formatID) else {
                return .unsupported("Unsupported Playback: lossy m4a content cannot preserve Bit Perfect Playback.")
            }

            let player = try AVAudioPlayer(contentsOf: request.fileURL)
            let deviceUID = Self.coreAudioDeviceUID(from: request.outputDevice)
            player.currentDevice = deviceUID
            guard player.currentDevice == deviceUID else {
                return .unsupported("Unsupported Playback: selected output device is not available to the CoreAudio playback path.")
            }
            if let resumeAtSeconds = request.resumeAtSeconds {
                player.currentTime = resumeAtSeconds
            }
            guard player.prepareToPlay(), player.play() else {
                return .unsupported("Unsupported Playback: CoreAudio playback path could not start.")
            }

            self.player = player
            self.durationSeconds = inspection.durationSeconds ?? (player.duration > 0 ? player.duration : nil)
            return .playing(
                PlaybackProgress(
                    elapsedSeconds: player.currentTime,
                    durationSeconds: self.durationSeconds
                )
            )
        } catch {
            return .unsupported("Unsupported Playback: Candidate Music File could not be validated by CoreAudio.")
        }
    }

    public func pause() async -> PlaybackPauseResult {
        guard let player = self.player else {
            return PlaybackPauseResult(progress: PlaybackProgress(elapsedSeconds: 0, durationSeconds: self.durationSeconds))
        }

        player.pause()
        return PlaybackPauseResult(
            progress: PlaybackProgress(
                elapsedSeconds: player.currentTime,
                durationSeconds: self.durationSeconds
            )
        )
    }

    private static func coreAudioDeviceUID(from outputDevice: OutputDevice) -> String {
        let prefix = "coreaudio:"
        guard outputDevice.id.hasPrefix(prefix) else {
            return outputDevice.id
        }
        return String(outputDevice.id.dropFirst(prefix.count))
    }

    private static func isSupportedLosslessSource(fileURL: URL, formatID: AudioFormatID) -> Bool {
        let fileExtension = fileURL.pathExtension.lowercased()
        if fileExtension == "m4a" {
            return formatID == kAudioFormatAppleLossless
        }
        return true
    }

    private static func inspectAudioFile(_ fileURL: URL) throws -> AudioFileInspection {
        var fileID: AudioFileID?
        let openStatus = AudioFileOpenURL(fileURL as CFURL, .readPermission, 0, &fileID)
        guard openStatus == noErr, let fileID else {
            throw CoreAudioPlaybackInspectionError.coreAudioStatus(openStatus)
        }
        defer {
            AudioFileClose(fileID)
        }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioFileGetProperty(
            fileID,
            kAudioFilePropertyDataFormat,
            &formatSize,
            &format
        )
        guard formatStatus == noErr else {
            throw CoreAudioPlaybackInspectionError.coreAudioStatus(formatStatus)
        }

        var duration = Float64(0)
        var durationSize = UInt32(MemoryLayout<Float64>.size)
        let durationStatus = AudioFileGetProperty(
            fileID,
            kAudioFilePropertyEstimatedDuration,
            &durationSize,
            &duration
        )
        let durationSeconds = durationStatus == noErr && duration.isFinite && duration > 0
            ? Double(duration)
            : nil

        return AudioFileInspection(formatID: format.mFormatID, durationSeconds: durationSeconds)
    }
}

private struct AudioFileInspection {
    let formatID: AudioFormatID
    let durationSeconds: Double?
}

private enum CoreAudioPlaybackInspectionError: Error {
    case coreAudioStatus(OSStatus)
}
