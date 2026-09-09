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

    /// A finger's path, built segment by segment and run as one touch
    /// through `ParityTouch`, so a drag can turn or reverse without lifting
    /// and can lift while still moving. Each segment is one keyframe: the
    /// daemon interpolates between keyframes at the display rate, and paths
    /// with keyframes a few milliseconds apart are played back compressed.
    struct Finger {
        private(set) var points: [CGPoint]
        private(set) var times: [Double]

        init(at start: CGPoint) {
            points = [start]
            times = [0]
        }

        var position: CGPoint { points.last! }
        var time: Double { times.last! }

        /// A straight segment at `speed` pt/s.
        mutating func line(to end: CGPoint, speed: CGFloat) {
            let from = position
            points.append(end)
            times.append(time + Double(hypot(end.x - from.x, end.y - from.y) / speed))
        }

        /// Keeps the finger still for `seconds`.
        mutating func hold(_ seconds: Double) {
            points.append(position)
            times.append(time + seconds)
        }

        /// Runs the path, lifting `after` seconds past the last point: 8 ms
        /// for a release while moving (a real finger's lift), longer for a
        /// release at rest.
        func lift(after: Double = 0.008) {
            let path = ParityPath(points: points.map { NSValue(cgPoint: $0) }, times: times.map { NSNumber(value: $0) }, lift: time + after)
            do {
                try ParityTouch.run([path])
            } catch {
                XCTFail("touch synthesis failed: \(error)")
            }
        }
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
    // Around the position threshold: 51 % of the page sprang back, 60 % popped.
    func testSwipe52Rest() { edgeSwipe(to: 0.52 + 0.04, speed: 300, rest: true) }
    func testSwipe54Rest() { edgeSwipe(to: 0.54 + 0.04, speed: 300, rest: true) }
    func testSwipe56Rest() { edgeSwipe(to: 0.56 + 0.04, speed: 300, rest: true) }
    func testSwipe58Rest() { edgeSwipe(to: 0.58 + 0.04, speed: 300, rest: true) }
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

    // MARK: Stage 5: the edge swipe on the zoom page. Each test opens the
    // Dunes poster, waits, then drags from the leading edge at the page's
    // vertical centre; names give the finger's end as a fraction of the
    // width and how it is released.

    func openDunes() {
        dunes.tap()
        hold(1.2)
    }

    /// The first 20 pt go at 300 pt/s whatever the speed: a first move that
    /// lands past the edge region misses the edge recognizer, and the poster
    /// pager takes the swipe instead.
    func zoomEdgeSwipe(to fraction: CGFloat, speed: CGFloat, rest: Bool) {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 24, y: 437), speed: 300)
        finger.line(to: CGPoint(x: 402 * fraction, y: 437), speed: speed)
        if rest { finger.hold(0.6) }
        finger.lift()
        hold(1.5)
    }

    func testZoomEdge20Rest() { zoomEdgeSwipe(to: 0.2, speed: 300, rest: true) }
    func testZoomEdge40Rest() { zoomEdgeSwipe(to: 0.4, speed: 300, rest: true) }
    func testZoomEdge60Rest() { zoomEdgeSwipe(to: 0.6, speed: 300, rest: true) }
    // Around the commit boundary: 36 % of the width (scale 0.76) sprang back
    // and 56 % (0.62) landed.
    func testZoomEdge44Rest() { zoomEdgeSwipe(to: 0.44, speed: 300, rest: true) }
    func testZoomEdge48Rest() { zoomEdgeSwipe(to: 0.48, speed: 300, rest: true) }
    func testZoomEdge52Rest() { zoomEdgeSwipe(to: 0.52, speed: 300, rest: true) }
    func testZoomEdge20Fling() { zoomEdgeSwipe(to: 0.2, speed: 1200, rest: false) }
    func testZoomEdge40Fling() { zoomEdgeSwipe(to: 0.4, speed: 800, rest: false) }
    func testZoomEdge60Fling() { zoomEdgeSwipe(to: 0.6, speed: 800, rest: false) }

    /// To 40 %, then 200 pt straight down, held and released at rest: the
    /// card follows the finger freely once it is off the edge.
    func testZoomEdge40Down() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 402 * 0.4, y: 437), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 402 * 0.4, y: 637), speed: 300)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

    /// To 20 %, then 300 pt down and 60 pt back up, for the vertical follow
    /// at a second scale and on the way back.
    func testZoomEdge20DownUp() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 402 * 0.2, y: 437), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 402 * 0.2, y: 737), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 402 * 0.2, y: 677), speed: 300)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

    /// To 40 %, then back to the edge, released while still moving.
    func testZoomEdge40Return() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 402 * 0.4, y: 437), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 20, y: 437), speed: 300)
        finger.lift()
        hold(1.5)
    }

    // MARK: Stage 4: the pan on the zoom page. Each test opens the Dunes
    // poster, waits, then drags down from a point on the art; names give the
    // finger's travel as a fraction of the screen height and how it is
    // released. The grab is at y = 160 so an 80 % travel stays on screen.

    static let grab = CGPoint(x: 201, y: 160)
    static let height: CGFloat = 874

    /// A straight drag down by `fraction` of the height at `speed` pt/s, the
    /// first 20 pt at 300 whatever the speed, so the scroll view hands the
    /// drag across before it is going fast.
    func zoomPan(to fraction: CGFloat, speed: CGFloat, rest: Bool, from: CGPoint = ParityDriver.grab) {
        openDunes()
        var finger = Finger(at: from)
        finger.line(to: CGPoint(x: from.x, y: from.y + 20), speed: 300)
        finger.line(to: CGPoint(x: from.x, y: from.y + Self.height * fraction), speed: speed)
        if rest { finger.hold(0.6) }
        finger.lift()
        hold(1.5)
    }

    func testZoomPan15Rest() { zoomPan(to: 0.15, speed: 300, rest: true) }
    func testZoomPan30Rest() { zoomPan(to: 0.3, speed: 300, rest: true) }
    func testZoomPan50Rest() { zoomPan(to: 0.5, speed: 300, rest: true) }
    func testZoomPan80Rest() { zoomPan(to: 0.8, speed: 300, rest: true) }
    // The commit table: three positions, released slow, medium and fast.
    func testZoomPan20Slow() { zoomPan(to: 0.2, speed: 150, rest: false) }
    func testZoomPan20Medium() { zoomPan(to: 0.2, speed: 400, rest: false) }
    func testZoomPan20Fast() { zoomPan(to: 0.2, speed: 800, rest: false) }
    func testZoomPan40Slow() { zoomPan(to: 0.4, speed: 150, rest: false) }
    func testZoomPan40Medium() { zoomPan(to: 0.4, speed: 400, rest: false) }
    func testZoomPan40Fast() { zoomPan(to: 0.4, speed: 800, rest: false) }
    func testZoomPan60Slow() { zoomPan(to: 0.6, speed: 150, rest: false) }
    func testZoomPan60Medium() { zoomPan(to: 0.6, speed: 400, rest: false) }
    func testZoomPan60Fast() { zoomPan(to: 0.6, speed: 800, rest: false) }
    // Around the rest boundary: 15 % of the height (0.914) sprang back and a
    // slow release at 20 % (0.884) landed.
    func testZoomPan17Rest() { zoomPan(to: 0.17, speed: 300, rest: true) }
    func testZoomPan19Rest() { zoomPan(to: 0.19, speed: 300, rest: true) }
    // The pivot: grabbed just under the bar, and low on the page. A grab
    // 12 pt under the bar (y = 115) does nothing natively.
    func testZoomPanTop30Rest() { zoomPan(to: 0.3, speed: 300, rest: true, from: CGPoint(x: 201, y: 130)) }
    func testZoomPanBottom20Rest() { zoomPan(to: 0.2, speed: 300, rest: true, from: CGPoint(x: 201, y: 680)) }

    /// To 50 %, then 120 pt back up at 800 pt/s, released while moving.
    func testZoomPan50UpFling() {
        openDunes()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: 201, y: 180), speed: 300)
        finger.line(to: CGPoint(x: 201, y: 160 + Self.height * 0.5), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 201, y: 160 + Self.height * 0.5 - 120), speed: 800)
        finger.lift()
        hold(1.5)
    }

    /// To 30 %, then sideways by `dx` at `speed`, held and released at rest.
    func zoomPanSideways(dx: CGFloat, speed: CGFloat) {
        openDunes()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: 201, y: 180), speed: 300)
        finger.line(to: CGPoint(x: 201, y: 160 + Self.height * 0.3), speed: 300)
        finger.hold(0.3)
        finger.line(to: CGPoint(x: 201 + dx, y: 160 + Self.height * 0.3), speed: speed)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

    func testZoomPan30Right() { zoomPanSideways(dx: 100, speed: 300) }
    func testZoomPan30Right50() { zoomPanSideways(dx: 50, speed: 300) }
    func testZoomPan30Right150() { zoomPanSideways(dx: 150, speed: 300) }
    func testZoomPan30Left150() { zoomPanSideways(dx: -150, speed: 300) }
    func testZoomPan30Left() { zoomPanSideways(dx: -100, speed: 300) }
    // As far as the finger can go, fast: the card meets the screen's edge.
    func testZoomPan30FarRight() { zoomPanSideways(dx: 195, speed: 600) }

    /// Scrolls the page up 200 pt, then drags 400 pt down in one motion: the
    /// list scrolls back to its top and hands the rest to the dismissal.
    func testZoomPanScrolled() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 201, y: 500))
        finger.line(to: CGPoint(x: 201, y: 300), speed: 300)
        finger.hold(0.8)
        finger.lift()
        hold(1.0)
        var again = Finger(at: CGPoint(x: 201, y: 300))
        again.line(to: CGPoint(x: 201, y: 700), speed: 300)
        again.hold(0.6)
        again.lift()
        hold(1.5)
    }

    /// Smoke test for the synthesizer: an edge swipe on a pushed page pops it.
    func testFingerPops() {
        pushFirstRow()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 320, y: 437), speed: 400)
        finger.hold(0.5)
        finger.lift()
        hold(1.0)
        XCTAssertTrue(app.staticTexts["Push — leading edge back swipe"].exists, "the swipe did not pop")
    }

}
