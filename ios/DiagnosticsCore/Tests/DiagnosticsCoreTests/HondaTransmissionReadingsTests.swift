import XCTest
@testable import DiagnosticsCore

final class HondaTransmissionReadingsTests: XCTestCase {
    func testDecodesCompleteTransportReplyWithoutPadding() throws {
        let reply = """
        18DAF11D 10 27 62 22 01 A5 A5 A5
        18DAF11D 21 A5 A5 A5 A5 05 13 01
        18DAF11D 22 62 04 2C A5 A5 A5 A5
        18DAF11D 23 A5 A5 A5 A5 A5 A5 A5
        18DAF11D 24 A5 A5 58 A5 A5 A5 A5
        18DAF11D 25 A5 A5 A5 A5 A5 EE EE
        >
        """
        let response = try XCTUnwrap(ELMResponseParser.parse(reply, for: .hondaTransmissionData).first)
        guard case .manufacturerData(let body) = response.outcome else {
            return XCTFail("Expected a Honda transmission data body.")
        }
        XCTAssertEqual(body.count, 36)
        let readings = try XCTUnwrap(HondaTransmissionReadings.decode(body: body))
        XCTAssertEqual(readings.atfCelsius, 48)
        XCTAssertEqual(readings.engineRPM, 1299)
        XCTAssertEqual(readings.inputRPM, 1068)
        XCTAssertEqual(readings.outputRPM, 354)
    }

    func testDecodesTemperatureAndThreeDistinctBigEndianSpeeds() throws {
        var body = Array(repeating: UInt8(0xA5), count: 36)
        body.replaceSubrange(7..<13, with: [0x05, 0x13, 0x01, 0x62, 0x04, 0x2C])
        body[26] = 0x58

        let readings = try XCTUnwrap(HondaTransmissionReadings.decode(body: body))
        XCTAssertEqual(readings.atfCelsius, 48)
        XCTAssertEqual(readings.engineRPM, 1299)
        XCTAssertEqual(readings.inputRPM, 1068)
        XCTAssertEqual(readings.outputRPM, 354)
    }

    func testPreservesSubzeroTemperatureAndStoppedShafts() throws {
        var body = Array(repeating: UInt8(0), count: 36)
        body[26] = 0x13

        let readings = try XCTUnwrap(HondaTransmissionReadings.decode(body: body))
        XCTAssertEqual(readings.atfCelsius, -21)
        XCTAssertEqual(readings.engineRPM, 0)
        XCTAssertEqual(readings.inputRPM, 0)
        XCTAssertEqual(readings.outputRPM, 0)
    }

    func testRequiresTheExactDataBodyLength() {
        for length in [0, 35, 37] {
            XCTAssertNil(HondaTransmissionReadings.decode(body: Array(repeating: 0, count: length)))
        }
    }
}
