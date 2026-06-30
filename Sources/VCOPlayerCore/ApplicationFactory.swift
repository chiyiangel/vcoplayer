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
    outputDeviceProvider: any OutputDeviceProviding = CoreAudioOutputDeviceProvider()
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

private actor PlayerStateStore {
    private var playbackList: [PlaybackListItem] = []
    private var selectedOutputDevice: OutputDevice?
    private let runtimeInfo: RuntimeInfo

    init(runtimeInfo: RuntimeInfo) {
        self.runtimeInfo = runtimeInfo
    }

    func status() -> PlayerStatus {
        PlayerStatus(
            playbackState: .idle,
            nowPlaying: nil,
            playbackList: self.playbackList,
            selectedOutputDevice: self.selectedOutputDevice,
            failureReason: nil,
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
