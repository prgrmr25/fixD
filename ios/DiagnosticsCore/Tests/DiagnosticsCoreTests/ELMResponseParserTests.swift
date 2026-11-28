import Foundation
import XCTest
@testable import DiagnosticsCore

final class ELMResponseParserTests: XCTestCase {
    func testDiagnosticRequestEncoderSupportsOnlyReadServices() {
        let requests: [(DiagnosticRequest, String)] = [
            (.currentData(.engineSpeed), "010C\r"),
            (.troubleCodes(.stored), "03\r"),
            (.troubleCodes(.pending), "07\r"),
            (.troubleCodes(.permanent), "0A\r")
        ]
        XCTAssertEqual(TroubleCodeCategory.allCases.map(\.rawValue), [0x03, 0x07, 0x0A])
        for (request, expected) in requests {
            XCTAssertEqual(ASCIIPromptFramer.encode(request), Array(expected.utf8))
        }
    }

    func testPublishedHeaderAndPaddingExample() throws {
        // Elm Electronics ELM327DSH, "Setting the Headers", p. 39.
        let replies = try ELMResponseParser.parse(
            "01 00\rSEARCHING...\r7E8 06 41 00 BE 3F B8 13 00\r>",
            for: .currentData(.supported01Through20)
        )
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first?.responder.hexIdentifier, "7E8")
        XCTAssertEqual(replies.first?.responder.width, .standard11Bit)
        XCTAssertEqual(replies.first?.payload, [0x41, 0x00, 0xBE, 0x3F, 0xB8, 0x13])
        XCTAssertEqual(
            replies.first?.outcome,
            .currentData(.supportedPIDs([1, 3, 4, 5, 6, 7, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 28, 31, 32]))
        )
    }

    func testCurrentDataKeepsEachResponderAndSupportsExtendedHeadersAndDLC() throws {
        let replies = try ELMResponseParser.parse(
            "18 DA F1 10 5 04 41 0C 1A F8\r\n18daf11804410c1c20\r\n",
            for: .currentData(.engineSpeed)
        )
        XCTAssertEqual(replies.map(\.responder.hexIdentifier), ["18DAF110", "18DAF118"])
        XCTAssertEqual(replies.map(\.responder.identifier), [0x18DAF110, 0x18DAF118])
        XCTAssertEqual(replies.map(\.responder.width), [.extended29Bit, .extended29Bit])
        XCTAssertEqual(replies.map(\.outcome), [.currentData(.measurement(1726, .rpm)), .currentData(.measurement(1800, .rpm))])
    }

    func testExtendedCANReplayKeepsCapabilityPagesAndMeasurementsByECU() throws {
        // Synthetic replies using the 29-bit addresses observed on the test vehicle.
        let firstPage = try ELMResponseParser.parse(
            "0100\r18DAF111 06 41 00 00 10 00 01 AA\r18 DA F1 1D 06 41 00 00 00 00 01\r>",
            for: .currentData(.supported01Through20)
        )
        XCTAssertEqual(firstPage.map(\.responder.hexIdentifier), ["18DAF111", "18DAF11D"])
        XCTAssertEqual(firstPage.map(\.outcome), [
            .currentData(.supportedPIDs([0x0C, 0x20])),
            .currentData(.supportedPIDs([0x20]))
        ])

        let secondPage = try ELMResponseParser.parse(
            "0120\r18DAF11D0641202000000155\r18 DA F1 11 06 41 20 80 00 00 01\r>",
            for: .currentData(.supported21Through40)
        )
        XCTAssertEqual(secondPage.map(\.responder.hexIdentifier), ["18DAF11D", "18DAF111"])
        XCTAssertEqual(secondPage.map(\.outcome), [
            .currentData(.supportedPIDs([0x23, 0x40])),
            .currentData(.supportedPIDs([0x21, 0x40]))
        ])

        let thirdPage = try ELMResponseParser.parse(
            "0140\r18 DA F1 11 06 41 40 40 00 00 10\r18DAF11D0641404000000000\r>",
            for: .currentData(.supported41Through60)
        )
        XCTAssertEqual(thirdPage.map(\.responder.hexIdentifier), ["18DAF111", "18DAF11D"])
        XCTAssertEqual(thirdPage.map(\.outcome), [
            .currentData(.supportedPIDs([0x42, 0x5C])),
            .currentData(.supportedPIDs([0x42]))
        ])

        let oilTemperature = try ELMResponseParser.parse(
            "015C\r18DAF11103415C8CAAAAAAAA\r>",
            for: .currentData(.engineOilTemperature)
        )
        XCTAssertEqual(oilTemperature.map(\.responder.hexIdentifier), ["18DAF111"])
        XCTAssertEqual(oilTemperature.map(\.outcome), [.currentData(.measurement(100, .celsius))])

        let voltage = try ELMResponseParser.parse(
            "0142\r18DAF11D 04 41 42 30 D4\r18 DA F1 11 04 41 42 36 B0\r>",
            for: .currentData(.controlModuleVoltage)
        )
        XCTAssertEqual(voltage.map(\.responder.hexIdentifier), ["18DAF11D", "18DAF111"])
        XCTAssertEqual(voltage.map(\.outcome), [
            .currentData(.measurement(12.5, .volts)),
            .currentData(.measurement(14, .volts))
        ])
    }

    func testEachDTCServiceAndEmptyPositiveList() throws {
        let replies = try ELMResponseParser.parse(
            "03\r7E8 06 43 02 01 33 D0 16 AA\r7E9 02 43 00\r",
            for: .troubleCodes(.stored)
        )
        XCTAssertEqual(replies.map(\.outcome), [.troubleCodes(["P0133", "U1016"]), .troubleCodes([])])
        XCTAssertEqual(try ELMResponseParser.parse("7e80447014006", for: .troubleCodes(.pending)).first?.outcome,
                       .troubleCodes(["C0006"]))
        XCTAssertEqual(try ELMResponseParser.parse("7E8 04 4A 01 80 0A", for: .troubleCodes(.permanent)).first?.outcome,
                       .troubleCodes(["B000A"]))
    }

    func testIndependentInterleavedISOTransportResponses() throws {
        let text = """
        7E8 10 0A 43 04 01 33 D0 16
        7E9 10 08 43 03 40 06 80 0A
        7E9 21 C0 99
        7E8 21 03 00 20 2A CC CC CC
        """
        let replies = try ELMResponseParser.parse(text, for: .troubleCodes(.stored))
        XCTAssertEqual(replies.map(\.responder.hexIdentifier), ["7E8", "7E9"])
        XCTAssertEqual(replies.map(\.outcome), [
            .troubleCodes(["P0133", "U1016", "P0300", "P202A"]),
            .troubleCodes(["C0006", "B000A", "U0099"])
        ])
    }

    func testISOTransportSequenceRollsOverAfterFifteen() throws {
        let codes = (1...60).map { UInt8($0) }
        let payload: [UInt8] = [0x43, UInt8(codes.count)] + codes.flatMap { [0, $0] }
        func line(_ frame: [UInt8]) -> String {
            "7E8 " + frame.map { String(format: "%02X", Int($0)) }.joined(separator: " ")
        }
        var lines = [line([0x10, UInt8(payload.count)] + Array(payload.prefix(6)))]
        for (index, offset) in stride(from: 6, to: payload.count, by: 7).enumerated() {
            let control = UInt8(0x20 | ((index + 1) & 0x0F))
            lines.append(line([control] + Array(payload.dropFirst(offset).prefix(7))))
        }
        let result = try ELMResponseParser.parse(lines.joined(separator: "\r"), for: .troubleCodes(.stored))
        XCTAssertEqual(result.first?.payload, payload)
        XCTAssertEqual(result.first?.outcome, .troubleCodes(codes.map { String(format: "P%04X", Int($0)) }))
    }

    func testNegativeResponsePreservesECUAndPendingCanPrecedeSuccess() throws {
        let reply = "7E8 03 7F 01 78\r7E9 03 7F 01 12\r7E8 04 41 0C 1A F8\r"
        let replies = try ELMResponseParser.parse(reply, for: .currentData(.engineSpeed))
        XCTAssertEqual(replies.map(\.responder.hexIdentifier), ["7E8", "7E9"])
        XCTAssertEqual(replies.map(\.outcome), [.currentData(.measurement(1726, .rpm)), .negativeResponse(code: 0x12)])
        let dtcResponse = try ELMResponseParser.parse("7E8 03 7F 0A 11", for: .troubleCodes(.permanent))
        XCTAssertEqual(dtcResponse.first?.outcome, .negativeResponse(code: 0x11))
    }

    func testHondaProbeAllowlistUsesFixedReadRequestsAndPhysicalCANAddresses() {
        let probes: [(HondaModuleProbe, UInt8, UInt16, String, String, String)] = [
            (.powertrain, 0x11, 0x2661, "18DA11F1", "18DAF111", "222661\r"),
            (.transmission, 0x1D, 0x2200, "18DA1DF1", "18DAF11D", "222200\r"),
            (.shawd, 0x25, 0x6119, "18DA25F1", "18DAF125", "226119\r"),
            (.absVSA, 0x28, 0x4000, "18DA28F1", "18DAF128", "224000\r"),
            (.tpms, 0x26, 0x6000, "18DA26F1", "18DAF126", "226000\r"),
            (.srs, 0x53, 0x8000, "18DA53F1", "18DAF153", "228000\r"),
            (.instrumentCluster, 0x60, 0x7000, "18DA60F1", "18DAF160", "227000\r")
        ]
        XCTAssertEqual(HondaModuleProbe.allCases, probes.map { $0.0 })
        for (probe, address, identifier, requestID, responseID, command) in probes {
            XCTAssertEqual(probe.ecuAddress, address)
            XCTAssertEqual(probe.dataIdentifier, identifier)
            XCTAssertEqual(probe.requestCANID, requestID)
            XCTAssertEqual(probe.responseCANID, responseID)
            XCTAssertEqual(ASCIIPromptFramer.encode(.hondaData(probe)), Array(command.utf8))
        }
    }

    func testHondaStandardControlClassifiesTheDirectedReply() {
        let expected = "18DAF111 06 41 00 00 10 00 01"
        let other = "18DAF11D 06 41 00 00 00 00 01"
        let cases: [(String, HondaStandardControlStatus)] = [
            ("01 00\r\(expected)\r>", .matched),
            (other, .otherResponder),
            ("\(expected)\r\(other)", .otherResponder),
            ("7E8 06 41 00 00 10 00 01", .otherResponder),
            ("18DAF111 03 7F 01 11", .invalid),
            ("18DAF111 06 41 20 00 10 00 01", .invalid),
            ("18DAF111 05 41 00 00 10 00", .invalid),
            ("\(expected)\rNO DATA", .invalid),
            ("CAN ERROR\r>", .invalid),
            ("0100\rNO DATA\r>", .noData)
        ]
        for (reply, status) in cases {
            XCTAssertEqual(HondaModuleProbe.powertrain.standardControlStatus(reply: reply), status, reply)
        }
        XCTAssertEqual(HondaModuleProbe.transmission.standardControlStatus(reply: other), .matched)
    }

    func testHondaFunctionalControlReportsOnlyCurrentPositiveExtendedResponders() {
        let reply = "0100\r18DAF11D06410000000001\r7E8 06 41 00 00 10 00 01\r"
            + "18DAF125 03 7F 01 11\r18 DA F1 11 06 41 00 00 10 00 01\r>"
        XCTAssertEqual(HondaModuleProbe.functionalControlResponders(reply: reply), ["18DAF111", "18DAF11D"])
        XCTAssertEqual(HondaModuleProbe.functionalControlResponders(reply: "18DAF11D06410000000001"), ["18DAF11D"])
        XCTAssertEqual(HondaModuleProbe.functionalControlResponders(reply: "NO DATA\r>"), [])
        XCTAssertEqual(HondaModuleProbe.functionalControlResponders(reply: "18DAF111 05 41 00 00 10 00"), [])
    }

    func testHondaProbeReassemblesFragmentedPositiveReplyAsOpaqueData() throws {
        var framer = ASCIIPromptFramer()
        XCTAssertEqual(try framer.consume(Array("22 26 61\r18DAF111100B6226".utf8)), [])
        XCTAssertEqual(try framer.consume(Array("61010203\r18 DA F1 11 21 04 05".utf8)), [])
        let replies = try framer.consume(Array(" 06 07 08 AA AA\r>".utf8))
        let reply = try XCTUnwrap(replies.first)
        let responses = try ELMResponseParser.parse(reply, for: .hondaData(.powertrain))
        XCTAssertEqual(responses.map(\.responder.hexIdentifier), ["18DAF111"])
        XCTAssertEqual(responses.first?.payload, [0x62, 0x26, 0x61, 1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(responses.first?.outcome, .manufacturerData([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    func testHondaProbeRejectsMismatchedDIDMissingDataAndWrongECU() {
        let source = CANResponder(identifier: 0x18DAF111, width: .extended29Bit)
        let other = CANResponder(identifier: 0x18DAF11D, width: .extended29Bit)
        let standard = CANResponder(identifier: 0x7E8, width: .standard11Bit)
        let cases: [(String, ELMResponseError)] = [
            ("18DAF111 04 62 26 60 01", .unexpectedResponse(responder: source)),
            ("18DAF111 03 62 26 61", .invalidManufacturerData(responder: source)),
            ("18DAF11D 04 62 26 61 01", .unexpectedResponder(expected: "18DAF111", received: other)),
            ("7E8 04 62 26 61 01", .unexpectedResponder(expected: "18DAF111", received: standard))
        ]
        for (reply, expected) in cases {
            XCTAssertThrowsError(try ELMResponseParser.parse(reply, for: .hondaData(.powertrain))) {
                XCTAssertEqual($0 as? ELMResponseError, expected, reply)
            }
        }
    }

    func testHondaProbeAcceptsOnlyItsTargetECUNegativeReply() throws {
        let request = DiagnosticRequest.hondaData(.absVSA)
        let match = try ELMResponseParser.parse("18DAF128 03 7F 22 31", for: request)
        XCTAssertEqual(match.first?.outcome, .negativeResponse(code: 0x31))

        let other = CANResponder(identifier: 0x18DAF125, width: .extended29Bit)
        XCTAssertThrowsError(try ELMResponseParser.parse("18DAF125 03 7F 22 31", for: request)) {
            XCTAssertEqual($0 as? ELMResponseError, .unexpectedResponder(expected: "18DAF128", received: other))
        }
        let target = CANResponder(identifier: 0x18DAF128, width: .extended29Bit)
        XCTAssertThrowsError(try ELMResponseParser.parse("18DAF128 03 7F 01 11", for: request)) {
            XCTAssertEqual($0 as? ELMResponseError, .unexpectedResponse(responder: target))
        }
    }

    func testRejectsAdapterStatusAndAmbiguousFrames() throws {
        let cases: [(String, ELMResponseError)] = [
            ("NO DATA\r>", .noData),
            ("010C\rSEARCHING...\r>", .emptyResponse),
            ("CAN ERROR\r>", .adapterStatus("CAN ERROR")),
            ("7E8 04 41 0C 1A F8\rNO DATA", .adapterStatus("NO DATA alongside CAN frames")),
            ("010C>>", .malformedReply),
            ("41 0C 1A F8\r>", .invalidFrame(line: 1)),
            ("7DF 04 41 0C 1A F8\r>", .invalidFrame(line: 1)),
            ("7E8 4 04 41 0C 1A F8\r>", .invalidFrame(line: 1)),
            ("7E8 04 41 0C +A F8\r>", .invalidFrame(line: 1))
        ]
        for (line, expected) in cases {
            XCTAssertThrowsError(try ELMResponseParser.parse(line, for: .currentData(.engineSpeed))) {
                XCTAssertEqual($0 as? ELMResponseError, expected, line)
            }
        }
    }

    func testRejectsWrongServiceAndIncompleteOrConflictingReplies() throws {
        let responder = CANResponder(identifier: 0x7E8, width: .standard11Bit)
        let cases: [(String, DiagnosticRequest, ELMResponseError)] = [
            ("7E8 03 7F 22 31", .troubleCodes(.stored), .unexpectedResponse(responder: responder)),
            ("7E8 02 43 03", .troubleCodes(.stored), .invalidTroubleCodes(responder: responder)),
            ("7E8 04 43 01 00 00", .troubleCodes(.stored), .invalidTroubleCodes(responder: responder)),
            ("7E8 10 0A 43 04 01 33 D0 16", .troubleCodes(.stored), .incompleteTransport(responder: responder)),
            ("7E8 10 0A 43 04 01 33 D0 16\r7E8 22 03 00 20 2A", .troubleCodes(.stored), .invalidTransport(responder: responder, line: 2)),
            ("7E8 07 41 0C 1A F8", .currentData(.engineSpeed), .invalidTransport(responder: responder, line: 1)),
            ("7E8 04 41 0D 1A F8", .currentData(.engineSpeed), .currentData(responder: responder, reason: .mismatchedPID(expected: 0x0C, received: 0x0D))),
            ("7E8 04 41 0C 1A F8\r7E8 04 41 0C 1C 20", .currentData(.engineSpeed), .conflictingResponses(responder: responder))
        ]
        for (line, request, expected) in cases {
            XCTAssertThrowsError(try ELMResponseParser.parse(line, for: request)) {
                XCTAssertEqual($0 as? ELMResponseError, expected, line)
            }
        }
    }
}
