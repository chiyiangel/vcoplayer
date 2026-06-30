import ArgumentParser
import Foundation

public struct VCOPlayerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vcoplayer",
        abstract: "Headless macOS music player remote server.",
        subcommands: [ServeCommand.self, DevicesCommand.self]
    )

    public init() {}
}

public struct DevicesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List local audio output devices."
    )

    public init() {}

    public mutating func run() throws {
        print(try Self.output(deviceProvider: CoreAudioOutputDeviceProvider()))
    }

    public static func output(deviceProvider: any OutputDeviceProviding) throws -> String {
        try deviceProvider.outputDevices()
            .map { "\($0.id)\t\($0.name)" }
            .joined(separator: "\n")
    }
}

public struct ServeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the VCO Player Remote API server."
    )

    @Option(help: "Music Library Root.")
    public var library: String

    @Option(help: "Remote Bind Address.")
    public var host: String = "127.0.0.1"

    @Option(help: "Remote API port.")
    public var port: Int = 8080

    public init() {}

    public mutating func validate() throws {
        try validateMusicLibraryRoot(URL(fileURLWithPath: self.library, isDirectory: true))
    }

    public mutating func run() async throws {
        let libraryRoot = URL(fileURLWithPath: self.library, isDirectory: true)
        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: self.host,
            port: self.port
        )
        print("API listening on http://\(self.host):\(self.port)")
        try await app.runService()
    }
}

public func validateMusicLibraryRoot(_ libraryRoot: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: libraryRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw MusicLibraryRootError.notDirectory(libraryRoot.path)
    }
}
