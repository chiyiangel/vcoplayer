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
    public let playbackList: [String]
    public let selectedOutputDevice: String?
    public let failureReason: String?
    public let runtimeInfo: RuntimeInfo
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
    port: Int
) throws -> some ApplicationProtocol {
    try validateMusicLibraryRoot(libraryRoot)

    let status = PlayerStatus(
        playbackState: .idle,
        nowPlaying: nil,
        playbackList: [],
        selectedOutputDevice: nil,
        failureReason: nil,
        runtimeInfo: RuntimeInfo(
            musicLibraryRoot: libraryRoot.path,
            serverHost: host,
            serverPort: port
        )
    )

    let router = RouterBuilder(context: BasicRouterRequestContext.self) {
        Get("/api/status") { _, _ in
            status
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
    }

    return Application(
        responder: router,
        configuration: ApplicationConfiguration(
            address: .hostname(host, port: port),
            serverName: "vcoplayer"
        )
    )
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
