import XCTest

final class GarageSignalUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDashboardAndSignalSearch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["2011 Acura MDX"].waitForExistence(timeout: 10))
        app.buttons["edit-gauges"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard gauges"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Signals"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("engine oil pressure")
        let measurement = app.descendants(matching: .any).matching(identifier: "Engine oil pressure").firstMatch
        XCTAssertTrue(measurement.waitForExistence(timeout: 5))
        XCTAssertTrue(measurement.label.contains("Unavailable"))
    }

    @MainActor
    func testAcuraModulesAndReadOnlyServiceGate() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Diagnostics"].tap()
        app.buttons["2011 Acura MDX modules"].tap()
        XCTAssertTrue(app.navigationBars["Vehicle modules"].waitForExistence(timeout: 5))
        app.buttons["shawd"].tap()
        XCTAssertTrue(app.navigationBars["SH-AWD"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Vehicle support unverified"].exists)
        XCTAssertTrue(app.buttons["connect-module-fixd"].exists)
        XCTAssertFalse(app.buttons["scan-module"].exists)
        XCTAssertFalse(app.buttons["share-module-scan"].exists)

        app.buttons["connect-module-fixd"].tap()
        let inspector = app.navigationBars["Bluetooth Inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 8))
        inspector.buttons.firstMatch.tap()
        app.buttons["Honda/Acura service functions"].tap()
        XCTAssertTrue(app.navigationBars["Service Functions"].waitForExistence(timeout: 5))
        let reset = app.descendants(matching: .any).matching(identifier: "PCM learned-value reset").firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertTrue(reset.label.contains("Unavailable"))
        XCTAssertFalse(app.buttons["PCM learned-value reset"].exists)
    }

    @MainActor
    func testLiveScanRequiresAnIdentifiedAdapter() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Diagnostics"].tap()
        app.buttons["Scan a vehicle with FIXD"].tap()
        XCTAssertTrue(app.navigationBars["Bluetooth Inspector"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Scan Nearby"].exists)
        XCTAssertFalse(app.buttons["Scan Vehicle"].exists)
        XCTAssertFalse(app.buttons["Start Live Readings"].exists)
        XCTAssertFalse(app.buttons["Stop Live Readings"].exists)
        XCTAssertFalse(app.buttons["Disconnect"].exists)
    }

    @MainActor
    func testDemoRecordingPersistsAndCanBeExported() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Drive Logs"].tap()
        let start = app.buttons["record-demo"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let savedSample = app.staticTexts.containing(NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]* samples saved$")).firstMatch
        XCTAssertTrue(savedSample.waitForExistence(timeout: 8))
        app.buttons["save-demo"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "export-demo").firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.tabBars.buttons["Drive Logs"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "export-demo").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testVehicleAndDemoRemainDistinctSources() {
        let app = XCUIApplication()
        app.launch()

        let connect = app.buttons["connect-vehicle"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Simulated telemetry"].exists)
        connect.tap()
        XCTAssertTrue(app.navigationBars["Bluetooth Inspector"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["Demo"].tap()
        XCTAssertTrue(app.staticTexts["Simulated telemetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(connect.exists)

        app.tabBars.buttons["Signals"].tap()
        XCTAssertTrue(app.navigationBars["Signals"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Simulated telemetry"].waitForExistence(timeout: 5))
        app.buttons["Vehicle"].tap()
        XCTAssertTrue(app.staticTexts["Vehicle monitoring inactive"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Simulated telemetry"].exists)
    }
}
