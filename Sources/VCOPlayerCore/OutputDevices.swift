import CoreAudio
import Foundation

public struct OutputDevice: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public protocol OutputDeviceProviding: Sendable {
    func outputDevices() throws -> [OutputDevice]
}

public struct CoreAudioOutputDeviceProvider: OutputDeviceProviding {
    public init() {}

    public func outputDevices() throws -> [OutputDevice] {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw CoreAudioOutputDeviceError.coreAudioStatus(status)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            throw CoreAudioOutputDeviceError.coreAudioStatus(status)
        }

        return try deviceIDs.compactMap { deviceID in
            guard try self.hasOutputStreams(deviceID) else {
                return nil
            }

            let name = try self.stringProperty(
                kAudioObjectPropertyName,
                for: deviceID
            )
            let uid = try self.stringProperty(
                kAudioDevicePropertyDeviceUID,
                for: deviceID
            )
            return OutputDevice(id: "coreaudio:\(uid)", name: name)
        }
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &streamsAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw CoreAudioOutputDeviceError.coreAudioStatus(status)
        }

        return dataSize > 0
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else {
            throw CoreAudioOutputDeviceError.coreAudioStatus(status)
        }
        guard let value else {
            throw CoreAudioOutputDeviceError.missingStringProperty
        }

        return value.takeUnretainedValue() as String
    }
}

public enum CoreAudioOutputDeviceError: Error, Equatable {
    case coreAudioStatus(OSStatus)
    case missingStringProperty
}
