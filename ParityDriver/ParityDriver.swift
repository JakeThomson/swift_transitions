import XCTest

/// Drives either app — the native reference or the Flutter example — through
/// the same scripted gestures, by coordinate, so a recording of each run
/// has the same input. Select the app with the `PARITY_APP` environment
/// variable (`native`, the default, or `flutter`).
final class ParityDriver: XCTestCase {
    static let bundleIds = [
        "native": "com.swifttransitions.NativeReference",
        "flutter": "com.example.swiftTransitionsExample",
    ]

    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        let which = ProcessInfo.processInfo.environment["PARITY_APP"] ?? "native"
        app = XCUIApplication(bundleIdentifier: Self.bundleIds[which]!)
        app.launchEnvironment["PARITY_SHOW_TOUCHES"] = ProcessInfo.processInfo.environment["PARITY_SHOW_TOUCHES"] ?? "1"
        app.launchEnvironment["PARITY_FLAT"] = ProcessInfo.processInfo.environment["PARITY_FLAT"] ?? "0"
        app.launch()
        // Let the first frame and any launch animation settle before a recording starts.
        sleep(2)
    }

    // MARK: Points, in the 402×874 pt layout both apps share.

    /// A point in the app's window, in points from its top left.
    func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Measured from the example at rest (stage 0): rows 44 pt tall from
    /// y = 107, the Dunes poster at (148, 250)–(268, 430), the bar's back
    /// button at (30, 81).
    var firstRow: XCUICoordinate { at(200, 129) }
    var secondRow: XCUICoordinate { at(200, 173) }
    var dunes: XCUICoordinate { at(208, 340) }
    var backButton: XCUICoordinate { at(30, 81) }
    var pageCentre: XCUICoordinate { at(201, 437) }

    /// Holds still for a while, for the recording.
    func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    /// A straight drag with the finger down for `duration` seconds,
    /// hold `holdAfter` seconds before lifting.
    func drag(from: XCUICoordinate, to: XCUICoordinate, duration: Double, holdAfter: Double = 0) {
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity(rawValue: max(1, distance(from, to) / duration)), thenHoldForDuration: holdAfter)
    }

    func distance(_ a: XCUICoordinate, _ b: XCUICoordinate) -> CGFloat {
        let dx = a.screenPoint.x - b.screenPoint.x, dy = a.screenPoint.y - b.screenPoint.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: Stage 0 smoke: push a row, pop it; zoom a poster, pop it.

    func testPushRow() {
        firstRow.tap()
        hold(1.5)
        backButton.tap()
        hold(1.5)
    }

    func testZoomPoster() {
        dunes.tap()
        hold(1.5)
        backButton.tap()
        hold(1.5)
    }
}
