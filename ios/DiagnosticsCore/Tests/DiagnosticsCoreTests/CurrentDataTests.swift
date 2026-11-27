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
