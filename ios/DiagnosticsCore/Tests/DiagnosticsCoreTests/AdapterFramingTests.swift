import XCTest
@testable import DiagnosticsCore

final class AdapterFramingTests: XCTestCase {
    func testAllowlistedRequestsAreUppercaseAndCarriageReturnTerminated() {
        XCTAssertEqual(ASCIIPromptFramer.encode(.engineSpeed), Array("010C\r".utf8))
        XCTAssertEqual(ASCIIPromptFramer.encode(.supported01Through20), Array("0100\r".utf8))
    }

    func testReplySpanningNotificationsWaitsForPrompt() throws {
        var framer = ASCIIPromptFramer()
        XCTAssertEqual(try framer.consume(Array("41 0C ".utf8)), [])
        XCTAssertEqual(try framer.consume(Array("1A F8\r".utf8)), [])
        XCTAssertEqual(try framer.consume(Array(">".utf8)), ["41 0C 1A F8\r"])
    }

    func testMultipleRepliesAndEmptyPrompt() throws {
        var framer = ASCIIPromptFramer()
        XCTAssertEqual(
            try framer.consume(Array("NO DATA\r>>OK\r>".utf8)),
            ["NO DATA\r", "", "OK\r"]
        )
    }

    func testMalformedAndStaleInputAreDiscarded() throws {
        var framer = ASCIIPromptFramer()
        _ = try framer.consume(Array("stale".utf8))
        framer.reset()
        XCTAssertEqual(try framer.consume(Array("OK>".utf8)), ["OK"])
        XCTAssertThrowsError(try framer.consume([0xFF])) { error in
            XCTAssertEqual(error as? AdapterFramingError, .invalidASCII(0xFF))
        }
        XCTAssertThrowsError(try framer.consume(Array(repeating: 0x20, count: 16_385))) { error in
            XCTAssertEqual(error as? AdapterFramingError, .responseTooLong)
        }
        XCTAssertEqual(try framer.consume(Array("OK>".utf8)), ["OK"])
    }
}
