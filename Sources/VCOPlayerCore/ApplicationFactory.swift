import Foundation
import Hummingbird
import HummingbirdRouter

public enum PlaybackState: String, Codable, Equatable, Sendable {
    case idle
    case playing
    case paused
    case stopped
    case unsupported
}

public struct RuntimeInfo: Codable, Equatable, Sendable {
    public let musicLibraryRoot: String
    public let serverHost: String
    public let serverPort: Int
}

public struct PlayerStatus: ResponseCodable, Equatable, Sendable {
    public let playbackState: PlaybackState
    public let nowPlaying: String?
    public let playbackList: [PlaybackListItem]
    public let selectedOutputDevice: OutputDevice?
    public let progress: PlaybackProgress?
    public let failureReason: String?
    public let runtimeInfo: RuntimeInfo
}

public struct PlaybackListItem: Codable, Equatable, Sendable {
    public let itemId: String
    public let path: String

    public init(itemId: String, path: String) {
        self.itemId = itemId
        self.path = path
    }
}

public struct RequestError: ResponseCodable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

private let missingOutputDeviceFailureReason = "Playback requires a selected Playback Output Device."
private let previousCommandRestartThresholdSeconds = 3.0

public enum MusicLibraryRootError: Error, CustomStringConvertible, Equatable {
    case notDirectory(String)

    public var description: String {
        switch self {
        case .notDirectory(let path):
            "Music Library Root is not a directory: \(path)"
        }
    }
}

public func buildApplication(
    libraryRoot: URL,
    host: String,
    port: Int,
    outputDeviceProvider: any OutputDeviceProviding = CoreAudioOutputDeviceProvider(),
    playbackController: any PlaybackControlling = CoreAudioPlaybackController()
) throws -> some ApplicationProtocol {
    try validateMusicLibraryRoot(libraryRoot)

    let playerState = PlayerStateStore(
        runtimeInfo: RuntimeInfo(
            musicLibraryRoot: libraryRoot.path,
            serverHost: host,
            serverPort: port
        )
    )

    let router = RouterBuilder(context: BasicRouterRequestContext.self) {
        Get("/api/status") { _, _ in
            await playerState.status()
        }
        Post("/api/play") { _, _ in
            PlaybackListMutationResponse.status(
                await playerState.play(libraryRoot: libraryRoot, playbackController: playbackController)
            )
        }
        Post("/api/pause") { _, _ in
            PlaybackListMutationResponse.status(
                await playerState.pause(playbackController: playbackController)
            )
        }
        Post("/api/next") { _, _ in
            PlaybackListMutationResponse.status(
                await playerState.next(libraryRoot: libraryRoot, playbackController: playbackController)
            )
        }
        Post("/api/previous") { _, _ in
            PlaybackListMutationResponse.status(
                await playerState.previous(libraryRoot: libraryRoot, playbackController: playbackController)
            )
        }
        Get("/api/devices") { _, _ in
            try outputDeviceProvider.outputDevices()
        }
        Get("/api/library") { request, _ in
            let relativePath = request.uri.queryParameters["path"].map(String.init) ?? ""
            do {
                return LibraryBrowserResponse.directory(
                    try browseLibraryDirectory(libraryRoot: libraryRoot, relativePath: relativePath)
                )
            } catch LibraryPathError.invalid {
                return LibraryBrowserResponse.requestError(
                    RequestError(
                        code: "invalid_library_path",
                        message: "Library path must be relative to the Music Library Root."
                    )
                )
            }
        }
        Post("/api/playback-list/files") { request, context in
            do {
                let pathRequest = try await request.decode(as: LibraryPathRequest.self, context: context)
                let filePath = try resolveCandidateMusicFile(libraryRoot: libraryRoot, relativePath: pathRequest.path)
                return PlaybackListMutationResponse.status(
                    await playerState.addFile(path: filePath)
                )
            } catch LibraryPathError.invalid {
                return PlaybackListMutationResponse.requestError(
                    RequestError(
                        code: "invalid_library_path",
                        message: "Playback List additions must use a Candidate Music File inside the Music Library Root."
                    )
                )
            }
        }
        Post("/api/playback-list/folders") { request, context in
            do {
                let pathRequest = try await request.decode(as: LibraryPathRequest.self, context: context)
                let filePaths = try collectCandidateMusicFiles(libraryRoot: libraryRoot, relativePath: pathRequest.path)
                return PlaybackListMutationResponse.status(
                    await playerState.addFiles(paths: filePaths)
                )
            } catch LibraryPathError.invalid {
                return PlaybackListMutationResponse.requestError(
                    RequestError(
                        code: "invalid_library_path",
                        message: "Folder Add must use a directory inside the Music Library Root."
                    )
                )
            }
        }
        Post("/api/playback-list/select") { request, context in
            let selectionRequest = try await request.decode(as: PlaybackListSelectionRequest.self, context: context)
            return PlaybackListMutationResponse.status(
                await playerState.selectPlaybackListItem(
                    itemID: selectionRequest.itemId,
                    libraryRoot: libraryRoot,
                    playbackController: playbackController
                )
            )
        }
        Post("/api/devices/select") { request, context in
            let selectionRequest = try await request.decode(as: OutputDeviceSelectionRequest.self, context: context)
            guard let outputDevice = try outputDeviceProvider.outputDevices().first(where: { $0.id == selectionRequest.deviceId }) else {
                return PlaybackListMutationResponse.requestError(
                    RequestError(
                        code: "invalid_output_device",
                        message: "Playback Output Device is not selectable."
                    )
                )
            }
            return PlaybackListMutationResponse.status(
                await playerState.selectOutputDevice(outputDevice)
            )
        }
    }

    return Application(
        responder: router,
        configuration: ApplicationConfiguration(
            address: .hostname(host, port: port),
            serverName: "vcoplayer"
        )
    )
}

private struct LibraryPathRequest: Decodable {
    let path: String
}

private struct OutputDeviceSelectionRequest: Decodable {
    let deviceId: String
}

private struct PlaybackListSelectionRequest: Decodable {
    let itemId: String
}

private actor PlayerStateStore {
    private var playbackList: [PlaybackListItem] = []
    private var selectedOutputDevice: OutputDevice?
    private var playbackState = PlaybackState.idle
    private var nowPlayingIndex: Int?
    private var progress: PlaybackProgress?
    private var failureReason: String?
    private let runtimeInfo: RuntimeInfo

    init(runtimeInfo: RuntimeInfo) {
        self.runtimeInfo = runtimeInfo
    }

    func status() -> PlayerStatus {
        PlayerStatus(
            playbackState: self.playbackState,
            nowPlaying: self.nowPlayingIndex.map { self.playbackList[$0].path },
            playbackList: self.playbackList,
            selectedOutputDevice: self.selectedOutputDevice,
            progress: self.progress,
            failureReason: self.failureReason,
            runtimeInfo: self.runtimeInfo
        )
    }

    func addFile(path: String) -> PlayerStatus {
        self.addFiles(paths: [path])
    }

    func addFiles(paths: [String]) -> PlayerStatus {
        for path in paths {
            self.playbackList.append(
                PlaybackListItem(itemId: UUID().uuidString, path: path)
            )
        }
        return self.status()
    }

    func selectOutputDevice(_ outputDevice: OutputDevice) -> PlayerStatus {
        self.selectedOutputDevice = outputDevice
        if self.playbackState == .unsupported,
           self.nowPlayingIndex == nil,
           self.failureReason == missingOutputDeviceFailureReason {
            self.playbackState = .idle
            self.failureReason = nil
        }
        return self.status()
    }

    func play(libraryRoot: URL, playbackController: any PlaybackControlling) async -> PlayerStatus {
        guard let outputDevice = self.selectedOutputDevice else {
            self.playbackState = .unsupported
            self.failureReason = missingOutputDeviceFailureReason
            return self.status()
        }
        guard !self.playbackList.isEmpty else {
            return self.status()
        }

        let playbackIndex = self.nowPlayingIndex ?? 0
        let resumeAtSeconds = self.playbackState == .paused ? self.progress?.elapsedSeconds : nil
        return await self.startPlayback(
            at: playbackIndex,
            libraryRoot: libraryRoot,
            outputDevice: outputDevice,
            playbackController: playbackController,
            resumeAtSeconds: resumeAtSeconds
        )
    }

    func next(libraryRoot: URL, playbackController: any PlaybackControlling) async -> PlayerStatus {
        guard let outputDevice = self.selectedOutputDevice else {
            self.playbackState = .unsupported
            self.failureReason = missingOutputDeviceFailureReason
            return self.status()
        }
        guard let nowPlayingIndex = self.nowPlayingIndex else {
            return await self.play(libraryRoot: libraryRoot, playbackController: playbackController)
        }

        let nextIndex = nowPlayingIndex + 1
        guard self.playbackList.indices.contains(nextIndex) else {
            await playbackController.stop()
            self.playbackState = .stopped
            self.progress = nil
            self.failureReason = nil
            return self.status()
        }

        return await self.startPlayback(
            at: nextIndex,
            libraryRoot: libraryRoot,
            outputDevice: outputDevice,
            playbackController: playbackController,
            resumeAtSeconds: nil
        )
    }

    func previous(libraryRoot: URL, playbackController: any PlaybackControlling) async -> PlayerStatus {
        guard let outputDevice = self.selectedOutputDevice else {
            self.playbackState = .unsupported
            self.failureReason = missingOutputDeviceFailureReason
            return self.status()
        }
        guard let nowPlayingIndex = self.nowPlayingIndex else {
            return await self.play(libraryRoot: libraryRoot, playbackController: playbackController)
        }

        let elapsedSeconds = self.progress?.elapsedSeconds ?? 0
        let targetIndex = elapsedSeconds < previousCommandRestartThresholdSeconds && nowPlayingIndex > 0
            ? nowPlayingIndex - 1
            : nowPlayingIndex

        return await self.startPlayback(
            at: targetIndex,
            libraryRoot: libraryRoot,
            outputDevice: outputDevice,
            playbackController: playbackController,
            resumeAtSeconds: nil
        )
    }

    func selectPlaybackListItem(
        itemID: String,
        libraryRoot: URL,
        playbackController: any PlaybackControlling
    ) async -> PlayerStatus {
        guard let outputDevice = self.selectedOutputDevice else {
            self.playbackState = .unsupported
            self.failureReason = missingOutputDeviceFailureReason
            return self.status()
        }
        guard let playbackIndex = self.playbackList.firstIndex(where: { $0.itemId == itemID }) else {
            return self.status()
        }

        return await self.startPlayback(
            at: playbackIndex,
            libraryRoot: libraryRoot,
            outputDevice: outputDevice,
            playbackController: playbackController,
            resumeAtSeconds: nil
        )
    }

    private func startPlayback(
        at playbackIndex: Int,
        libraryRoot: URL,
        outputDevice: OutputDevice,
        playbackController: any PlaybackControlling,
        resumeAtSeconds: Double?
    ) async -> PlayerStatus {
        let item = self.playbackList[playbackIndex]
        let result = await playbackController.start(
            PlaybackStartRequest(
                fileURL: libraryRoot.appendingPathComponent(item.path),
                relativePath: item.path,
                outputDevice: outputDevice,
                resumeAtSeconds: resumeAtSeconds
            )
        )

        switch result {
        case .playing(let progress):
            self.nowPlayingIndex = playbackIndex
            self.playbackState = .playing
            self.progress = progress
            self.failureReason = nil
        case .unsupported(let failureReason):
            self.nowPlayingIndex = playbackIndex
            self.playbackState = .unsupported
            self.progress = nil
            self.failureReason = failureReason
        }
        return self.status()
    }

    func pause(playbackController: any PlaybackControlling) async -> PlayerStatus {
        guard self.playbackState == .playing, self.nowPlayingIndex != nil else {
            return self.status()
        }

        let pauseResult = await playbackController.pause()
        self.playbackState = .paused
        self.progress = pauseResult.progress
        self.failureReason = nil
        return self.status()
    }
}

private enum LibraryBrowserResponse: ResponseGenerator {
    case directory(LibraryDirectory)
    case requestError(RequestError)

    func response(from request: Request, context: some RequestContext) throws -> Response {
        switch self {
        case .directory(let directory):
            return try directory.response(from: request, context: context)
        case .requestError(let requestError):
            var response = try requestError.response(from: request, context: context)
            response.status = .badRequest
            return response
        }
    }
}

private enum PlaybackListMutationResponse: ResponseGenerator {
    case status(PlayerStatus)
    case requestError(RequestError)

    func response(from request: Request, context: some RequestContext) throws -> Response {
        switch self {
        case .status(let status):
            return try status.response(from: request, context: context)
        case .requestError(let requestError):
            var response = try requestError.response(from: request, context: context)
            response.status = .badRequest
            return response
        }
    }
}
