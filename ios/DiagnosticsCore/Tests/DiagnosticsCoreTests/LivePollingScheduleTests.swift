import XCTest
@testable import DiagnosticsCore

final class LivePollingScheduleTests: XCTestCase {
    func testPrioritiesAreFirstAndSecondariesRotateWithoutDuplicateReads() {
        var schedule = LivePollingSchedule(available: [
            .vehicleSpeed, .controlModuleVoltage, .engineSpeed, .coolantTemperature,
            .controlModuleVoltage, .engineSpeed,
        ])
        XCTAssertEqual(schedule.next(), [.engineSpeed, .vehicleSpeed, .controlModuleVoltage])
        XCTAssertEqual(schedule.next(), [.engineSpeed, .vehicleSpeed, .coolantTemperature])
        XCTAssertEqual(schedule.next(), [.engineSpeed, .vehicleSpeed, .controlModuleVoltage])
        XCTAssertEqual(schedule.emptySweepLimit, 3)
    }

    func testSecondaryOnlyVehicleGetsAFullRotationBeforeEmptySweepsEnd() {
        let secondaries: [CurrentDataPID] = [
            .coolantTemperature, .engineOilTemperature, .throttlePosition, .controlModuleVoltage,
        ]
        var schedule = LivePollingSchedule(available: secondaries)
        XCTAssertEqual(schedule.emptySweepLimit, secondaries.count)
        for pid in secondaries {
            XCTAssertEqual(schedule.next(), [pid])
        }
        XCTAssertEqual(schedule.next(), [.coolantTemperature])
    }

    func testEmptyAndPriorityOnlySchedules() {
        var empty = LivePollingSchedule(available: [])
        XCTAssertEqual(empty.next(), [])
        XCTAssertEqual(empty.emptySweepLimit, 3)

        var speedOnly = LivePollingSchedule(available: [.vehicleSpeed])
        XCTAssertEqual(speedOnly.next(), [.vehicleSpeed])
        XCTAssertEqual(speedOnly.next(), [.vehicleSpeed])
    }

    func testDelayUsesOnlyTheRemainderOfTheHalfSecondSweepInterval() {
        XCTAssertEqual(LivePollingSchedule.delay(after: .zero), .milliseconds(500))
        XCTAssertEqual(LivePollingSchedule.delay(after: .milliseconds(120)), .milliseconds(380))
        XCTAssertEqual(LivePollingSchedule.delay(after: .milliseconds(500)), .zero)
        XCTAssertEqual(LivePollingSchedule.delay(after: .milliseconds(830)), .zero)
    }
}
