import CoreAudio
import Foundation

/// Lookups over the system's audio devices.
enum AudioDevices {
    static func all() -> [AudioObjectID] {
        HAL.objectIDs(HAL.systemObject, kAudioHardwarePropertyDevices)
    }

    static func defaultOutput() -> AudioObjectID? {
        let device = HAL.value(HAL.systemObject, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
        return device == kAudioObjectUnknown ? nil : device
    }

    static func uid(of device: AudioObjectID) -> String? {
        HAL.string(device, kAudioDevicePropertyDeviceUID)
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        var address = HAL.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                HAL.systemObject, &address, UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device
            )
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Whether the device has streams in the given scope (input or output).
    static func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        !HAL.objectIDs(device, kAudioDevicePropertyStreams, scope: scope).isEmpty
    }
}

/// A failed Core Audio call, with the operation for the log.
struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed: \(Self.fourCharacterCode(status)) (\(status))"
    }

    /// Core Audio errors are usually four-character codes like '!hog'.
    static func fourCharacterCode(_ status: OSStatus) -> String {
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian) { Array($0) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "\(status)" }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

@discardableResult
func check(_ status: OSStatus, _ operation: String) throws(CoreAudioError) -> OSStatus {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    return status
}
