/// Keeps an item visible for a short time after it stops being active, so a row doesn't vanish
/// and reappear when an app pauses between two tracks.
///
/// Time is passed in (monotonic seconds) so the behavior is testable.
public struct Linger<ID: Hashable & Sendable>: Sendable {
    public let duration: Double
    private var lastActive: [ID: Double] = [:]

    public init(duration: Double) {
        self.duration = duration
    }

    /// Records which items are active now and returns the ones to show: active ones, plus inactive
    /// ones that were active less than `duration` seconds ago.
    public mutating func update(active: Set<ID>, now: Double) -> Set<ID> {
        for id in active {
            lastActive[id] = now
        }
        lastActive = lastActive.filter { id, time in active.contains(id) || now - time < duration }
        return Set(lastActive.keys)
    }

    /// When the next lingering item expires, if any: the moment to call `update` again.
    public func nextExpiry(active: Set<ID>) -> Double? {
        lastActive
            .filter { !active.contains($0.key) }
            .map { $0.value + duration }
            .min()
    }
}
