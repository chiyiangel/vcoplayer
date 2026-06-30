import Foundation
import HummingbirdTesting
import NIOCore
import VCOPlayerCore

enum TestFailure: Error, CustomStringConvertible {
    case expectationFailed(String)

    var description: String {
        switch self {
        case .expectationFailed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure.expectationFailed(message)
    }
}

@main
struct BackendTestRunner {
    static func main() async {
        do {
            try await statusReturnsIdlePlayerStatusForValidMusicLibraryRoot()
            print("PASS statusReturnsIdlePlayerStatusForValidMusicLibraryRoot")
            try rejectsInvalidMusicLibraryRoot()
            print("PASS rejectsInvalidMusicLibraryRoot")
            try serveCommandUsesLocalOnlyDefaults()
            print("PASS serveCommandUsesLocalOnlyDefaults")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }

    static func statusReturnsIdlePlayerStatusForValidMusicLibraryRoot() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/status")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .idle, "expected idle Playback State")
                try expect(status.nowPlaying == nil, "expected no Now Playing entry")
                try expect(status.playbackList.isEmpty, "expected empty Playback List")
                try expect(status.selectedOutputDevice == nil, "expected no selected Playback Output Device")
                try expect(status.failureReason == nil, "expected no Playback Failure Reason")
                try expect(status.runtimeInfo.musicLibraryRoot == libraryRoot.path, "expected Runtime Info to include Music Library Root")
                try expect(status.runtimeInfo.serverHost == "127.0.0.1", "expected Runtime Info to include server host")
                try expect(status.runtimeInfo.serverPort == 0, "expected Runtime Info to include server port")
            }
        }
    }

    static func rejectsInvalidMusicLibraryRoot() throws {
        let missingRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try buildApplication(
                libraryRoot: missingRoot,
                host: "127.0.0.1",
                port: 8080
            )
            throw TestFailure.expectationFailed("expected invalid Music Library Root to be rejected")
        } catch TestFailure.expectationFailed {
            throw TestFailure.expectationFailed("expected invalid Music Library Root to be rejected")
        } catch {
            // Any domain error is enough for this first startup-boundary behavior.
        }
    }

    static func serveCommandUsesLocalOnlyDefaults() throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        var command = try ServeCommand.parse([
            "--library",
            libraryRoot.path,
        ])

        try expect(command.library == libraryRoot.path, "expected CLI library option to be parsed")
        try expect(command.host == "127.0.0.1", "expected local-only default host")
        try expect(command.port == 8080, "expected default API port")
        try command.validate()
    }
}
