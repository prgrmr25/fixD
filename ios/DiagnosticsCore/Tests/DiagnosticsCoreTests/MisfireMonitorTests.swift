import Foundation
import XCTest
@testable import DiagnosticsCore

final class MisfireMonitorTests: XCTestCase {
    func testCapabilityPagesAdvertiseAbsoluteMonitorIDsAndTheNextPage() throws {
        let pageIDs: [UInt8] = [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0]
        XCTAssertEqual(MisfireMonitorID.capabilityPages.map(\.rawValue), pageIDs)
        for page in MisfireMonitorID.capabilityPages {
            let hex = String(format: "%02X", Int(page.rawValue))
            let request = DiagnosticRequest.monitorData(page)
            XCTAssertEqual(ASCIIPromptFramer.encode(request), Array("06\(hex)\r".utf8))
            let reply = "18DAF111 06 46 \(hex) 80 00 00 01 AA"
            XCTAssertEqual(try ELMResponseParser.parse(reply, for: request).first?.outcome,
                           .monitorData(.supportedMonitors([page.rawValue + 1, page.rawValue + 32])))
        }

        let reply = "06A0\r18DAF111 06 46 A0 7E 00 00 00\r18DAF11D 06 46 A0 20 00 00 00\r>"
        let responses = try ELMResponseParser.parse(reply, for: .monitorData(.supportedA1ThroughC0))
        XCTAssertEqual(responses.map(\.responder.hexIdentifier), ["18DAF111", "18DAF11D"])
        XCTAssertEqual(responses.map(\.outcome), [
            .monitorData(.supportedMonitors(Set(MisfireMonitorID.cylinders.map(\.rawValue)))),
            .monitorData(.supportedMonitors([0xA3]))
        ])
        XCTAssertEqual(MisfireMonitorID.cylinders.compactMap(\.cylinderNumber), Array(1...6))
    }

    func testCycleCountUsesUnsignedBigEndianValueFromTheCorrectRecordAndECU() throws {
        let reply = """
        06 A2
        18DAF111 10 13 46 A2 0B 24 01 02
        18DAF11D 10 0A 46 A2 0C 24 00 07
        18DAF111 21 00 00 FF FF A2 0C 24
        18DAF11D 21 00 00 FF FF AA AA AA
        18DAF111 22 FE DC 00 00 FF FF AA
        >
        """
        let responses = try ELMResponseParser.parse(reply, for: .monitorData(.cylinder1))
        XCTAssertEqual(responses.map(\.responder.hexIdentifier), ["18DAF111", "18DAF11D"])
        XCTAssertEqual(responses.map(\.outcome), [.monitorData(.cycleMisfireCount(0xFEDC)), .monitorData(.cycleMisfireCount(7))])
    }

    func testResponderLimitIgnoresUnrelatedIncompleteTransport() throws {
        let request = DiagnosticRequest.monitorData(.supported01Through20)
        let reply = "18DAF11D 10 09 46 00 00 00 00 01\r18DAF111 06 46 00 00 00 00 01\r>"
        let result = try ELMResponseParser.parse(reply, for: request, limitingToResponder: "18DAF111")
        XCTAssertEqual(result.map(\.responder.hexIdentifier), ["18DAF111"])
        XCTAssertEqual(result.first?.outcome, .monitorData(.supportedMonitors([0x20])))
        XCTAssertTrue(try ELMResponseParser.parse(reply, for: request, limitingToResponder: "18DAF155").isEmpty)
    }

    func testUninitializedAndAverageOnlyResultDoNotReportACycleCount() throws {
        let request = DiagnosticRequest.monitorData(.cylinder6)
        let head = "18DAF111 10 0A 46 A7"
        let cases: [(String, MisfireMonitorValue)] = [
            ("\(head) 0C 24 00 00\r18DAF111 21 00 00 00 00", .cycleMisfireCount(nil)),
            ("\(head) 0B 24 00 02\r18DAF111 21 00 00 FF FF", .cycleMisfireCount(nil)),
            ("\(head) 0C 24 00 00\r18DAF111 21 00 00 FF FF", .cycleMisfireCount(0))
        ]
        for (reply, expected) in cases {
            XCTAssertEqual(try ELMResponseParser.parse(reply, for: request).first?.outcome, .monitorData(expected))
        }
        XCTAssertEqual(try ELMResponseParser.parse("18DAF111 03 7F 06 31", for: request).first?.outcome,
                       .negativeResponse(code: 0x31))
    }

    func testMonitorRejectsMismatchedIDsScalingAndTruncatedRecords() {
        let source = CANResponder(identifier: 0x18DAF111, width: .extended29Bit)
        let bitmap = DiagnosticRequest.monitorData(.supportedA1ThroughC0)
        let cycle = DiagnosticRequest.monitorData(.cylinder1)
        let head = "18DAF111 10 0A 46 A2"
        let cases: [(String, DiagnosticRequest, ELMResponseError)] = [
            ("18DAF111 06 46 80 00 00 00 00", bitmap,
             .monitorData(responder: source, reason: .mismatchedMonitor(expected: 0xA0, received: 0x80))),
            ("18DAF111 05 46 A0 00 00 00", bitmap, .monitorData(responder: source, reason: .invalidCapabilityLength)),
            ("\(head) 0C 25 00 06\r18DAF111 21 00 00 FF FF", cycle,
             .monitorData(responder: source, reason: .unexpectedScaling(0x25))),
            ("18DAF111 10 09 46 A2 0C 24 00 06\r18DAF111 21 00 00 FF", cycle,
             .monitorData(responder: source, reason: .invalidRecordLength)),
            ("\(head) 0C 24 00 06", cycle, .incompleteTransport(responder: source)),
            ("18DAF111 03 7F 01 31", cycle, .unexpectedResponse(responder: source)),
            ("18DAF111 10 13 46 A2 0B 24 00 02\r18DAF111 21 00 00 FF FF A3 0C 24\r18DAF111 22 00 07 00 00 FF FF", cycle,
             .monitorData(responder: source, reason: .mismatchedMonitor(expected: 0xA2, received: 0xA3))),
            ("18DAF111 10 13 46 A2 0C 24 00 02\r18DAF111 21 00 00 FF FF A2 0C 24\r18DAF111 22 00 07 00 00 FF FF", cycle,
             .monitorData(responder: source, reason: .duplicateCycleTest))
        ]
        for (reply, request, expected) in cases {
            XCTAssertThrowsError(try ELMResponseParser.parse(reply, for: request)) {
                XCTAssertEqual($0 as? ELMResponseError, expected, reply)
            }
        }
    }
}
