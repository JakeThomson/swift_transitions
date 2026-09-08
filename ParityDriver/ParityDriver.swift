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

    /// A straight drag replayed as a chain of short segments so its speed is
    /// what the plan says: XCUITest's own velocity is a hint, not a rate.
    /// `speed` is in points per second; `holdAfter` keeps the finger still
    /// before lifting, for a release at rest.
    func drag(from: CGPoint, to: CGPoint, speed: CGFloat, holdAfter: Double = 0) {
        let start = at(from.x, from.y)
        let end = at(to.x, to.y)
        let seconds = Double(hypot(to.x - from.x, to.y - from.y) / speed)
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: holdAfter)
        _ = seconds
    }

    // MARK: Stage 0 smoke: push a row, pop it; zoom a poster, pop it.

    /// Each transition is run twice and the second is the one measured:
    /// the first build of a page in a Flutter debug build (the only kind
    /// the simulator runs) takes tens of milliseconds while the animation
    /// clock is already running, which no release build does.
    func testPushRow() {
        for _ in 0..<2 {
            firstRow.tap()
            hold(1.5)
            backButton.tap()
            hold(1.5)
        }
    }

    func testZoomPoster() {
        for _ in 0..<2 {
            dunes.tap()
            hold(1.5)
            backButton.tap()
            hold(1.5)
        }
    }

    // MARK: Stage 2: the back swipe. Each test pushes the first row, waits,
    // then drags from the leading edge. Names encode the case: position as
    // a fraction of the width, then how it is released.

    func pushFirstRow() {
        firstRow.tap()
        hold(1.2)
    }

    /// An edge drag to `fraction` of the width at `speed` pt/s, released at
    /// rest (`rest`) or lifted while still moving at that speed.
    func edgeSwipe(to fraction: CGFloat, speed: CGFloat, rest: Bool) {
        pushFirstRow()
        drag(from: CGPoint(x: 4, y: 437), to: CGPoint(x: 402 * fraction, y: 437), speed: speed, holdAfter: rest ? 0.6 : 0)
        hold(1.2)
    }

    func testSwipe20Rest() { edgeSwipe(to: 0.2, speed: 300, rest: true) }
    func testSwipe45Rest() { edgeSwipe(to: 0.45, speed: 300, rest: true) }
    func testSwipe55Rest() { edgeSwipe(to: 0.55, speed: 300, rest: true) }
    func testSwipe80Rest() { edgeSwipe(to: 0.8, speed: 300, rest: true) }
    func testSwipe20Fling() { edgeSwipe(to: 0.2, speed: 1200, rest: false) }
    func testSwipe35Slow() { edgeSwipe(to: 0.35, speed: 150, rest: false) }
    func testSwipe35Medium() { edgeSwipe(to: 0.35, speed: 400, rest: false) }
    func testSwipe65Slow() { edgeSwipe(to: 0.65, speed: 150, rest: false) }

    /// Dragged to 70 %, then pulled back 60 pt and lifted while moving.
    func testSwipe70PullBack() {
        pushFirstRow()
        let start = at(4, 437)
        let far = at(402 * 0.7, 437)
        let back = at(402 * 0.7 - 60, 437)
        start.press(forDuration: 0.02, thenDragTo: far, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.3)
        far.press(forDuration: 0.0, thenDragTo: back, withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0)
        hold(1.2)
    }
}
