import XCTest
@testable import DiagnosticsCore

final class CurrentDataTests: XCTestCase {
    func testPublishedRPMExample() throws {
        // Elm Electronics ELM327DSH, "Talking to the Vehicle", p. 29.
        XCTAssertEqual(CurrentDataPID.engineSpeed.requestPayload, [0x01, 0x0C])
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x0C, 0x1A, 0xF8], for: .engineSpeed),
            .measurement(1726, .rpm)
        )
    }

    func testSupportedBitmapIsMostSignificantBitFirst() throws {
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x00, 0x81, 0, 0, 1], for: .supported01Through20),
            .supportedPIDs([1, 8, 32])
        )
    }

    func testExtendedCapabilityBitmapsReturnAbsolutePIDValues() throws {
        XCTAssertTrue(CurrentDataPID.supported01Through20.isCapabilityBitmap)
        XCTAssertTrue(CurrentDataPID.supported21Through40.isCapabilityBitmap)
        XCTAssertTrue(CurrentDataPID.supported41Through60.isCapabilityBitmap)
        XCTAssertEqual(CurrentDataPID.supported21Through40.requestPayload, [0x01, 0x20])
        XCTAssertEqual(CurrentDataPID.supported41Through60.requestPayload, [0x01, 0x40])
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x20, 0x81, 0, 0, 0x01], for: .supported21Through40),
            .supportedPIDs([0x21, 0x28, 0x40])
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x40, 0xC0, 0, 0, 0x11], for: .supported41Through60),
            .supportedPIDs([0x41, 0x42, 0x5C, 0x60])
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x40, 0, 0, 0, 0], for: .supported41Through60),
            .supportedPIDs([])
        )
    }

    func testOilTemperatureAndControlModuleVoltageUseStandardScales() throws {
        XCTAssertFalse(CurrentDataPID.engineOilTemperature.isCapabilityBitmap)
        XCTAssertFalse(CurrentDataPID.controlModuleVoltage.isCapabilityBitmap)
        XCTAssertEqual(CurrentDataPID.engineOilTemperature.requestPayload, [0x01, 0x5C])
        XCTAssertEqual(CurrentDataPID.controlModuleVoltage.requestPayload, [0x01, 0x42])
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x5C, 0x8C], for: .engineOilTemperature),
            .measurement(100, .celsius)
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x5C, 0], for: .engineOilTemperature),
            .measurement(-40, .celsius)
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x42, 0x36, 0xB0], for: .controlModuleVoltage),
            .measurement(14, .volts)
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x42, 0x30, 0xD4], for: .controlModuleVoltage),
            .measurement(12.5, .volts)
        )
    }

    func testExtendedRepliesRejectWrongLengthsAndDoNotConfusePIDs() {
        let cases: [(CurrentDataPID, [UInt8], CurrentDataDecodingError)] = [
            (.supported21Through40, [0x41, 0x20, 0x80, 0, 0], .invalidLength(expected: 4, received: 3)),
            (.supported41Through60, [0x41, 0x40, 0, 0, 0, 0, 0], .invalidLength(expected: 4, received: 5)),
            (.engineOilTemperature, [0x41, 0x5C], .invalidLength(expected: 1, received: 0)),
            (.engineOilTemperature, [0x41, 0x5C, 0x8C, 0], .invalidLength(expected: 1, received: 2)),
            (.controlModuleVoltage, [0x41, 0x42, 0x36], .invalidLength(expected: 2, received: 1)),
            (.controlModuleVoltage, [0x41, 0x42, 0x36, 0xB0, 0], .invalidLength(expected: 2, received: 3)),
            (
                .engineOilTemperature, [0x41, 0x40, 0xC0, 0, 0, 0x11],
                .mismatchedPID(expected: 0x5C, received: 0x40)
            ),
            (
                .supported41Through60, [0x41, 0x42, 0x36, 0xB0],
                .mismatchedPID(expected: 0x40, received: 0x42)
            )
        ]
        for (pid, payload, expected) in cases {
            XCTAssertThrowsError(try CurrentDataDecoder.decode(payload, for: pid)) { error in
                XCTAssertEqual(error as? CurrentDataDecodingError, expected)
            }
        }
    }

    func testStandardMeasurementScaling() throws {
        let examples: [(CurrentDataPID, UInt8, CurrentDataValue)] = [
            (.coolantTemperature, 0x46, .measurement(30, .celsius)),
            (.vehicleSpeed, 88, .measurement(88, .kilometersPerHour)),
            (.shortTermFuelTrimBank1, 0, .measurement(-100, .percent)),
            (.longTermFuelTrimBank1, 128, .measurement(0, .percent)),
            (.shortTermFuelTrimBank2, 192, .measurement(50, .percent)),
            (.longTermFuelTrimBank2, 255, .measurement(99.21875, .percent)),
            (.ignitionAdvance, 0x90, .measurement(8, .degreesBeforeTopDeadCenter)),
        ]
        for (pid, byte, expected) in examples {
            XCTAssertEqual(try CurrentDataDecoder.decode([0x41, pid.rawValue, byte], for: pid), expected)
        }
    }

    func testCalculatedLoadAndThrottleAreReadOnlyWithStandardPercentScaling() throws {
        XCTAssertEqual(CurrentDataPID.calculatedEngineLoad.requestPayload, [0x01, 0x04])
        XCTAssertEqual(CurrentDataPID.throttlePosition.requestPayload, [0x01, 0x11])
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x04, 0x33], for: .calculatedEngineLoad),
            .measurement(20, .percent)
        )
        XCTAssertEqual(
            try CurrentDataDecoder.decode([0x41, 0x11, 0xCC], for: .throttlePosition),
            .measurement(80, .percent)
        )
    }

    func testRejectsMalformedUnmatchedAndNegativeResponses() {
        let cases: [([UInt8], CurrentDataDecodingError)] = [
            ([0x41], .malformedPayload),
            ([0x43, 0x0C], .unexpectedService(0x43)),
            ([0x41, 0x0D, 0x1A, 0xF8], .mismatchedPID(expected: 0x0C, received: 0x0D)),
            ([0x41, 0x0C, 0x1A], .invalidLength(expected: 2, received: 1)),
            ([0x41, 0x0C, 0x1A, 0xF8, 0x00], .invalidLength(expected: 2, received: 3)),
            ([0x7F, 0x01], .malformedPayload),
            ([0x7F, 0x22, 0x31], .unexpectedService(0x22)),
            ([0x7F, 0x01, 0x11], .negativeResponse(code: 0x11)),
        ]
        for (bytes, expected) in cases {
            XCTAssertThrowsError(try CurrentDataDecoder.decode(bytes, for: .engineSpeed)) { error in
                XCTAssertEqual(error as? CurrentDataDecodingError, expected)
            }
        }
    }
}
