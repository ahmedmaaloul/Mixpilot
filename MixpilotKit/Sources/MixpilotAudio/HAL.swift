import CoreAudio
import Foundation
import os

/// Thin, typed wrappers over the Core Audio property functions.
enum HAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Reads a fixed-size value (integers, floats, object IDs). Nil if the property is missing.
    static func value<T: BitwiseCopyable>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: T
    ) -> T? {
        var address = address(selector, scope: scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    /// Reads a `UInt32` flag as a Bool.
    static func flag(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool? {
        value(object, selector, scope: scope, initial: UInt32(0)).map { $0 != 0 }
    }

    /// Reads an array of object IDs (process lists, device lists).
    static func objectIDs(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Reads a CFString property (the caller of the HAL owns the returned string).
    static func string(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &result) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let string = result?.takeRetainedValue() else { return nil }
        let value = string as String
        return value.isEmpty ? nil : value
    }
}

/// A property listener registered with a block on a queue. Call `remove()` to unregister it;
/// Core Audio needs the same block and queue for that, which this object keeps.
final class HALListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var isRegistered: Bool

    /// Registers `handler` to run on `queue` whenever the property changes. Nil if the HAL refuses
    /// (the object is already gone, for example).
    init?(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue,
        handler: @escaping () -> Void
    ) {
        self.object = object
        self.address = HAL.address(selector, scope: scope, element: element)
        self.queue = queue
        self.block = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        guard status == noErr else { return nil }
        isRegistered = true
    }

    func remove() {
        guard isRegistered else { return }
        isRegistered = false
        // Fails harmlessly when the object is already gone.
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }

    deinit {
        remove()
    }
}

extension Logger {
    /// Logs under Mixpilot's subsystem: `log stream --predicate 'subsystem == "app.mixpilot.mac"'`.
    static func mixpilot(_ category: String) -> Logger {
        Logger(subsystem: "app.mixpilot.mac", category: category)
    }
}
