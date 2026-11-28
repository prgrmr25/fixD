/// Selects a serial sweep from the live measurements supported by the connected vehicle.
public struct LivePollingSchedule: Sendable {
    private let priorities: [CurrentDataPID]
    private let secondaries: [CurrentDataPID]
    private var nextSecondary = 0

    public init(available: [CurrentDataPID]) {
        let priorityOrder: [CurrentDataPID] = [.engineSpeed, .vehicleSpeed]
        let supported = Set(available)
        priorities = priorityOrder.filter { supported.contains($0) }
        var seen = Set(priorityOrder)
        secondaries = available.filter { seen.insert($0).inserted }
    }

    /// Gives every secondary a turn before ending a run with no usable samples.
    public var emptySweepLimit: Int { max(3, secondaries.count) }

    public mutating func next() -> [CurrentDataPID] {
        guard !secondaries.isEmpty else { return priorities }
        let secondary = secondaries[nextSecondary]
        nextSecondary = (nextSecondary + 1) % secondaries.count
        return priorities + [secondary]
    }

    public static func delay(after elapsed: Duration) -> Duration {
        max(.zero, .milliseconds(500) - elapsed)
    }
}
