import CoreAudio
import Foundation
import MixpilotCore
import os

/// Watches the audio system's client processes and publishes a fresh list whenever one starts,
/// stops, or starts or stops playing or recording.
///
/// All state is confined to `queue`, which is also where Core Audio calls the listeners. Bursts of
/// changes (an app opening several streams at once) are coalesced into one snapshot.
public final class ProcessMonitor: @unchecked Sendable {
    /// The current processes, newest only: a slow consumer skips intermediate states.
    public let processes: AsyncStream<[AudioProcess]>

    private let continuation: AsyncStream<[AudioProcess]>.Continuation
    private let queue = DispatchQueue(label: "app.mixpilot.process-monitor", qos: .userInitiated)
    private let log = Logger.mixpilot("processes")

    // Confined to `queue`.
    private var listListener: HALListener?
    private var processListeners: [AudioObjectID: [HALListener]] = [:]
    private var identities: [AudioObjectID: Identity] = [:]
    private var order: [AudioObjectID] = []
    private var isPublishScheduled = false

    /// What doesn't change during a process's lifetime, read once.
    private struct Identity {
        var pid: Int32
        var bundleID: String?
        var parentPID: Int32?
        var responsiblePID: Int32?
    }

    public init() {
        (processes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func start() {
        queue.async { [self] in
            guard listListener == nil else { return }
            if !Responsibility.isAvailable {
                log.notice("Responsible-process lookup unavailable; grouping by parent and bundle ID only")
            }
            listListener = HALListener(
                object: HAL.systemObject,
                selector: kAudioHardwarePropertyProcessObjectList,
                queue: queue
            ) { [weak self] in
                self?.refreshProcessList()
            }
            refreshProcessList()
        }
    }

    public func stop() {
        queue.sync {
            listListener?.remove()
            listListener = nil
            processListeners.values.joined().forEach { $0.remove() }
            processListeners = [:]
            identities = [:]
            order = []
        }
        continuation.finish()
    }

    /// Requests a new snapshot without a change in Core Audio (for example after an app launched,
    /// so helpers that couldn't be grouped yet get another chance).
    public func republish() {
        queue.async { [self] in scheduleSnapshot() }
    }

    // MARK: - On the queue

    private func refreshProcessList() {
        let current = HAL.objectIDs(HAL.systemObject, kAudioHardwarePropertyProcessObjectList)
        let currentSet = Set(current)

        for gone in processListeners.keys where !currentSet.contains(gone) {
            processListeners[gone]?.forEach { $0.remove() }
            processListeners[gone] = nil
            identities[gone] = nil
        }
        for object in current where processListeners[object] == nil {
            // IsRunningOutput and IsRunningInput never notify (macOS 27). IsRunning does, and
            // Devices (wildcard scope) does when a process opens or closes an input or output;
            // the snapshot then re-reads both flags.
            let watched: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
                (kAudioProcessPropertyIsRunning, kAudioObjectPropertyScopeGlobal),
                (kAudioProcessPropertyDevices, kAudioObjectPropertyScopeWildcard),
            ]
            processListeners[object] = watched.compactMap { selector, scope in
                HALListener(object: object, selector: selector, scope: scope, queue: queue) { [weak self] in
                    self?.scheduleSnapshot()
                }
            }
            if let pid = HAL.value(object, kAudioProcessPropertyPID, initial: pid_t(0)), pid > 0 {
                identities[object] = Identity(
                    pid: pid,
                    bundleID: HAL.string(object, kAudioProcessPropertyBundleID),
                    parentPID: ProcessTree.parentPID(of: pid),
                    responsiblePID: Responsibility.responsiblePID(for: pid)
                )
            }
        }
        order = current
        scheduleSnapshot()
    }

    private func scheduleSnapshot() {
        guard !isPublishScheduled else { return }
        isPublishScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
            isPublishScheduled = false
            publish()
        }
    }

    private func publish() {
        let snapshot = order.compactMap { object -> AudioProcess? in
            guard let identity = identities[object] else { return nil }
            return AudioProcess(
                id: object,
                pid: identity.pid,
                bundleID: identity.bundleID,
                isRunningOutput: HAL.flag(object, kAudioProcessPropertyIsRunningOutput) ?? false,
                isRunningInput: HAL.flag(object, kAudioProcessPropertyIsRunningInput) ?? false,
                parentPID: identity.parentPID,
                responsiblePID: identity.responsiblePID
            )
        }
        continuation.yield(snapshot)
    }
}
