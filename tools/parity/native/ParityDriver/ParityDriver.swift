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
        app.launchEnvironment["PARITY_UIKIT"] = ProcessInfo.processInfo.environment["PARITY_UIKIT"] ?? "0"
        app.launchEnvironment["PARITY_ART_4_3"] = ProcessInfo.processInfo.environment["PARITY_ART_4_3"] ?? "0"
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
    /// The Aurora still, (16, 507)–(176, 597), in the row under the posters.
    var auroraStill: XCUICoordinate { at(96, 552) }
    /// The Dunes film, (148, 674)–(268, 854), in the row under the stills.
    var dunesFilm: XCUICoordinate { at(208, 764) }
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
            Finger.lift([self], after: after)
        }

        /// Runs several fingers' paths as one touch sequence — a pinch — all
        /// down together at time zero and each lifting `after` its own last
        /// point.
        static func lift(_ fingers: [Finger], after: Double = 0.008) {
            let paths = fingers.map {
                ParityPath(points: $0.points.map { NSValue(cgPoint: $0) }, times: $0.times.map { NSNumber(value: $0) }, lift: $0.time + after)
            }
            do {
                try ParityTouch.run(paths)
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

    /// The aligned zoom: a still whose page keeps the art under a title.
    /// Native runs it with `PARITY_UIKIT=1`, the UIKit scene being the only
    /// one with an `alignmentRectProvider`.
    func testZoomStill() {
        for _ in 0..<2 {
            auroraStill.tap()
            hold(1.5)
            backButton.tap()
            hold(1.5)
        }
    }

    /// The film zoom: a poster whose page leads with a backdrop, another
    /// picture at another size, so the whole page shrinks into the poster.
    func testZoomFilm() {
        for _ in 0..<2 {
            dunesFilm.tap()
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

    /// A drag started in the middle of the second row's page, not at its
    /// edge: the example's `BackGestureRegion.anywhere` page against a plain
    /// native push, which pops from anywhere on this runtime.
    func anywhereSwipe(from x: CGFloat, travel: CGFloat, speed: CGFloat, rest: Bool) {
        secondRow.tap()
        hold(1.2)
        var finger = Finger(at: CGPoint(x: x, y: 437))
        finger.line(to: CGPoint(x: x + travel, y: 437), speed: speed)
        if rest { finger.hold(0.6) }
        finger.lift()
        hold(1.5)
    }

    // Released at rest over a grid of start × travel, for the commit rule
    // from a touch that is not at the edge; two flings.
    func testAnywhereS100T120Rest() { anywhereSwipe(from: 100, travel: 120, speed: 300, rest: true) }
    func testAnywhereS100T150Rest() { anywhereSwipe(from: 100, travel: 150, speed: 300, rest: true) }
    func testAnywhereS100T180Rest() { anywhereSwipe(from: 100, travel: 180, speed: 300, rest: true) }
    func testAnywhereS100T210Rest() { anywhereSwipe(from: 100, travel: 210, speed: 300, rest: true) }
    func testAnywhereS200T80Rest() { anywhereSwipe(from: 200, travel: 80, speed: 300, rest: true) }
    func testAnywhereS200T100Rest() { anywhereSwipe(from: 200, travel: 100, speed: 300, rest: true) }
    func testAnywhereS200T120Rest() { anywhereSwipe(from: 200, travel: 120, speed: 300, rest: true) }
    func testAnywhereS200T140Rest() { anywhereSwipe(from: 200, travel: 140, speed: 300, rest: true) }
    func testAnywhereS200T160Rest() { anywhereSwipe(from: 200, travel: 160, speed: 300, rest: true) }
    func testAnywhereS300T40Rest() { anywhereSwipe(from: 300, travel: 40, speed: 300, rest: true) }
    func testAnywhereS300T50Rest() { anywhereSwipe(from: 300, travel: 50, speed: 300, rest: true) }
    func testAnywhereS300T60Rest() { anywhereSwipe(from: 300, travel: 60, speed: 300, rest: true) }
    func testAnywhereS300T70Rest() { anywhereSwipe(from: 300, travel: 70, speed: 300, rest: true) }
    func testAnywhereS300T80Rest() { anywhereSwipe(from: 300, travel: 80, speed: 300, rest: true) }
    func testAnywhereS100T190Rest() { anywhereSwipe(from: 100, travel: 190, speed: 300, rest: true) }
    func testAnywhereS100T200Rest() { anywhereSwipe(from: 100, travel: 200, speed: 300, rest: true) }
    func testAnywhereS200T170Rest() { anywhereSwipe(from: 200, travel: 170, speed: 300, rest: true) }
    func testAnywhereS200T180Rest() { anywhereSwipe(from: 200, travel: 180, speed: 300, rest: true) }
    func testAnywhereS200T190Rest() { anywhereSwipe(from: 200, travel: 190, speed: 300, rest: true) }
    func testAnywhereS200T200Rest() { anywhereSwipe(from: 200, travel: 200, speed: 300, rest: true) }
    func testAnywhereS200T160RestB() { anywhereSwipe(from: 200, travel: 160, speed: 300, rest: true) }
    func testAnywhereS200T160RestC() { anywhereSwipe(from: 200, travel: 160, speed: 300, rest: true) }
    func testAnywhereS100T80Fling() { anywhereSwipe(from: 100, travel: 80, speed: 1200, rest: false) }
    func testAnywhereS300T40Fling() { anywhereSwipe(from: 300, travel: 40, speed: 1200, rest: false) }

    /// The same mid-page drag on a zoom page: the film page, whose only
    /// scroll view is vertical, and the poster pager on its first poster.
    func filmAnywhere(from x: CGFloat = 200, travel: CGFloat) {
        dunesFilm.tap()
        hold(1.5)
        var finger = Finger(at: CGPoint(x: x, y: 437))
        finger.line(to: CGPoint(x: x + travel, y: 437), speed: 300)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

    func testFilmAnywhere200Rest() { filmAnywhere(travel: 200) }
    func testFilmAnywhereT120Rest() { filmAnywhere(travel: 120) }
    func testFilmAnywhereT140Rest() { filmAnywhere(travel: 140) }
    func testFilmAnywhereT160Rest() { filmAnywhere(travel: 160) }
    func testFilmAnywhereT180Rest() { filmAnywhere(travel: 180) }
    func testFilmAnywhereS100T150Rest() { filmAnywhere(from: 100, travel: 150) }
    func testFilmAnywhereS100T200Rest() { filmAnywhere(from: 100, travel: 200) }
    func testFilmAnywhereS300T60Rest() { filmAnywhere(from: 300, travel: 60) }
    func testFilmAnywhereS300T80Rest() { filmAnywhere(from: 300, travel: 80) }

    func testFilmAnywhere100Fling() {
        dunesFilm.tap()
        hold(1.5)
        var finger = Finger(at: CGPoint(x: 100, y: 437))
        finger.line(to: CGPoint(x: 180, y: 437), speed: 1200)
        finger.lift()
        hold(1.5)
    }

    func testAuroraAnywhere200Rest() {
        at(88, 340).tap()
        hold(1.5)
        var finger = Finger(at: CGPoint(x: 200, y: 437))
        finger.line(to: CGPoint(x: 400, y: 437), speed: 300)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

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

    /// The still page dragged: a pan released early, at rest, springs
    /// back; a pan flung lands; an edge swipe flung lands — the aligned
    /// page's interactive dismissal, every kind (stage 3, aligned).
    func stillOpen() {
        auroraStill.tap()
        hold(1.5)
    }

    func testStillPan30Rest() {
        stillOpen()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + 20), speed: 300)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + Self.height * 0.3), speed: 300)
        finger.hold(0.6)
        finger.lift()
        hold(1.5)
    }

    func testStillPan40Fast() {
        stillOpen()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + 20), speed: 300)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + Self.height * 0.4), speed: 800)
        finger.lift()
        hold(1.5)
    }

    func testStillEdge60Fling() {
        stillOpen()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 24, y: 437), speed: 300)
        finger.line(to: CGPoint(x: 402 * 0.6, y: 437), speed: 800)
        finger.lift()
        hold(1.5)
    }

    /// The film page dragged home: a pan flung and an edge swipe flung,
    /// the landings the film's poster is meant to be met at.
    func filmOpen() {
        dunesFilm.tap()
        hold(1.5)
    }

    func testFilmPan40Fast() {
        filmOpen()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + 20), speed: 300)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + Self.height * 0.4), speed: 800)
        finger.lift()
        hold(1.5)
    }

    func testFilmEdge60Fling() {
        filmOpen()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 24, y: 437), speed: 300)
        finger.line(to: CGPoint(x: 402 * 0.6, y: 437), speed: 800)
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

    /// Thrown out at 2500 pt/s, past the speed native's landings stop
    /// coming down at: an uncapped quickening lands this in 60 ms, which
    /// reads as the card vanishing rather than flying home.
    func testZoomEdge50Thrown() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 24, y: 437), speed: 300)
        finger.line(to: CGPoint(x: 402 * 0.5, y: 437), speed: 2500)
        finger.lift()
        hold(1.5)
    }

    /// Out to 65 % and down 200 pt in one move, released still going: the
    /// landing then carries the card on both axes at once, which is where
    /// a card that left before it had arrived showed itself.
    func testZoomEdge65DownFling() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 4, y: 437))
        finger.line(to: CGPoint(x: 24, y: 437), speed: 300)
        finger.line(to: CGPoint(x: 402 * 0.65, y: 637), speed: 900)
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

    // MARK: Stage 6: pinches on the zoom page.

    static let centre = CGPoint(x: 201, y: 437)
    /// The fingers' starting distance, either side of the page's centre on
    /// the poster art.
    static let span: CGFloat = 300

    /// The two fingers `span` apart, vertically about `centre`.
    static func pinchFingers(at centre: CGPoint = ParityDriver.centre) -> (Finger, Finger) {
        (Finger(at: CGPoint(x: centre.x, y: centre.y - span / 2)),
         Finger(at: CGPoint(x: centre.x, y: centre.y + span / 2)))
    }

    /// Closes both fingers toward the centre until their distance is `scale`
    /// of the start, each at `speed` pt/s, and lifts at rest or while moving.
    func zoomPinch(to scale: CGFloat, speed: CGFloat, rest: Bool) {
        openDunes()
        var (a, b) = Self.pinchFingers()
        let half = Self.span * scale / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: speed)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: speed)
        if rest { a.hold(0.6); b.hold(0.6) }
        Finger.lift([a, b])
        hold(1.5)
    }

    func testZoomPinch90Rest() { zoomPinch(to: 0.9, speed: 300, rest: true) }
    func testZoomPinch80Rest() { zoomPinch(to: 0.8, speed: 300, rest: true) }
    func testZoomPinch70Rest() { zoomPinch(to: 0.7, speed: 300, rest: true) }
    func testZoomPinch60Rest() { zoomPinch(to: 0.6, speed: 300, rest: true) }
    func testZoomPinch50Rest() { zoomPinch(to: 0.5, speed: 300, rest: true) }
    func testZoomPinch40Rest() { zoomPinch(to: 0.4, speed: 300, rest: true) }
    // Either side of the boundary: 0.5 sprang back, 0.4 landed.
    func testZoomPinch45Rest() { zoomPinch(to: 0.45, speed: 300, rest: true) }
    func testZoomPinch48Rest() { zoomPinch(to: 0.48, speed: 300, rest: true) }
    func testZoomPinch80Slow() { zoomPinch(to: 0.8, speed: 150, rest: false) }
    func testZoomPinch80Fast() { zoomPinch(to: 0.8, speed: 800, rest: false) }
    func testZoomPinch60Slow() { zoomPinch(to: 0.6, speed: 150, rest: false) }
    func testZoomPinch60Fast() { zoomPinch(to: 0.6, speed: 800, rest: false) }
    // Released moving near the boundary: whether the fingers' distance or
    // the card's lagging scale decides, and whether speed counts.
    func testZoomPinch55Fast() { zoomPinch(to: 0.55, speed: 800, rest: false) }
    func testZoomPinch45Fast() { zoomPinch(to: 0.45, speed: 800, rest: false) }
    func testZoomPinch45Medium() { zoomPinch(to: 0.45, speed: 400, rest: false) }
    func testZoomPinch40Fast() { zoomPinch(to: 0.4, speed: 800, rest: false) }

    /// Closes to `scale`, then turns both fingers about the centre by
    /// `degrees` (clockwise on screen) along an arc, holds, and lifts.
    func zoomRotate(degrees: CGFloat, scale: CGFloat) {
        openDunes()
        var (a, b) = Self.pinchFingers()
        let half = Self.span * scale / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
        a.hold(0.3); b.hold(0.3)
        let steps = Int(max(4, degrees.magnitude / 5))
        for i in 1...steps {
            let angle = degrees * CGFloat(i) / CGFloat(steps) * .pi / 180
            let dx = half * sin(angle), dy = half * cos(angle)
            a.line(to: CGPoint(x: Self.centre.x + dx, y: Self.centre.y - dy), speed: 200)
            b.line(to: CGPoint(x: Self.centre.x - dx, y: Self.centre.y + dy), speed: 200)
        }
        a.hold(0.6); b.hold(0.6)
        Finger.lift([a, b])
        hold(1.5)
    }

    /// Closes to `scale` and then turns by `degrees` while carrying the
    /// fingers' focal point by `by`, all at once, and lifts at rest: a
    /// pinch, a pan and a turn together, released below the dismiss
    /// threshold so the card lands on its poster.
    func zoomPinchRotatePan(scale: CGFloat, degrees: CGFloat, by: CGVector) {
        openDunes()
        var (a, b) = Self.pinchFingers()
        let half = Self.span * scale / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
        a.hold(0.2); b.hold(0.2)
        let steps = 8
        for i in 1...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let angle = degrees * f * .pi / 180
            let centre = CGPoint(x: Self.centre.x + by.dx * f, y: Self.centre.y + by.dy * f)
            let dx = half * sin(angle), dy = half * cos(angle)
            a.line(to: CGPoint(x: centre.x + dx, y: centre.y - dy), speed: 200)
            b.line(to: CGPoint(x: centre.x - dx, y: centre.y + dy), speed: 200)
        }
        a.hold(0.6); b.hold(0.6)
        Finger.lift([a, b])
        hold(1.5)
    }

    func testZoomPinchRotatePanDismiss() {
        zoomPinchRotatePan(scale: 0.38, degrees: 20, by: CGVector(dx: 70, dy: 90))
    }

    func testZoomRotate15() { zoomRotate(degrees: 15, scale: 0.7) }
    func testZoomRotate45() { zoomRotate(degrees: 45, scale: 0.5) }
    /// Only a turn, the fingers never closing.
    func testZoomRotateOnly() { zoomRotate(degrees: 30, scale: 1.0) }

    /// Closes to 0.7, then carries both fingers 100 pt right and 60 down.
    func testZoomPinchMove() {
        openDunes()
        var (a, b) = Self.pinchFingers()
        let half = Self.span * 0.7 / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
        a.hold(0.3); b.hold(0.3)
        a.line(to: CGPoint(x: Self.centre.x + 100, y: Self.centre.y - half + 60), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x + 100, y: Self.centre.y + half + 60), speed: 300)
        a.hold(0.6); b.hold(0.6)
        Finger.lift([a, b])
        hold(1.5)
    }

    /// Spreads the fingers to 1.3 of their distance: a pinch out.
    func testZoomPinchOpen() { zoomPinch(to: 1.3, speed: 300, rest: true) }

    /// Closes to 0.6, then opens back to 0.9 and lifts at rest.
    func testZoomPinchReopen() {
        openDunes()
        var (a, b) = Self.pinchFingers()
        for scale in [0.6, 0.9] as [CGFloat] {
            let half = Self.span * scale / 2
            a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
            b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
            a.hold(0.3); b.hold(0.3)
        }
        a.hold(0.3); b.hold(0.3)
        Finger.lift([a, b])
        hold(1.5)
    }

    /// Scrolls the page up 200 pt and lifts, then pinches to 0.6 over the
    /// scrolled page.
    func testZoomPinchScrolled() {
        openDunes()
        var finger = Finger(at: CGPoint(x: 201, y: 500))
        finger.line(to: CGPoint(x: 201, y: 300), speed: 300)
        finger.hold(0.8)
        finger.lift()
        hold(1.0)
        var (a, b) = Self.pinchFingers()
        let half = Self.span * 0.6 / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
        a.hold(0.6); b.hold(0.6)
        Finger.lift([a, b])
        hold(1.5)
    }

    /// Smoke test for the synthesizer: an edge swipe on a pushed page pops it.
    // MARK: Stage 7: interruptions. A second finger lands on a point the
    // card covers all the way — (208, 400): inside the poster at home and
    // the page's art when open — after the tap that starts a push or the
    // lift that starts a landing. It is its own touch sequence, and the
    // daemon reports a sequence played about 240 ms after its last event,
    // so the finger lands about 250 ms after the tap's lift or the pan's:
    // fingers in one sequence must land together (the daemon plays a path
    // that starts later as a move of the finger before it, which never
    // lifts) and it refuses a sequence while another plays. The recording's
    // rings say when the finger landed.

    static let catchPoint = CGPoint(x: 208, y: 400)

    /// Taps the Dunes poster (down 50 ms), then lands a finger on the
    /// flying card, holds it `hold` seconds, drags it down `drag` points at
    /// `speed` and lifts at rest, or while moving if `rest` is false.
    func catchPush(hold: Double, drag: CGFloat = 0, speed: CGFloat = 300, rest: Bool = true) {
        var tap = Finger(at: CGPoint(x: 208, y: 340))
        tap.hold(0.042)
        tap.lift()
        var catcher = Finger(at: Self.catchPoint)
        if hold > 0 { catcher.hold(hold) }
        if drag > 0 {
            catcher.line(to: CGPoint(x: Self.catchPoint.x, y: Self.catchPoint.y + drag), speed: speed)
        }
        if rest { catcher.hold(0.6) }
        catcher.lift()
        self.hold(1.5)
    }

    func testCatchPushHold() { catchPush(hold: 0.5) }
    func testCatchPushDrag() { catchPush(hold: 0.3, drag: 200) }
    func testCatchPushDragNow() { catchPush(hold: 0, drag: 200) }
    func testCatchPushFlick() { catchPush(hold: 0, drag: 100, speed: 800, rest: false) }

    /// Taps the poster, then pinches the flying card to 0.6 at 300 pt/s a
    /// finger and releases at rest.
    func testCatchPushPinch() {
        var tap = Finger(at: CGPoint(x: 208, y: 340))
        tap.hold(0.042)
        tap.lift()
        var (a, b) = Self.pinchFingers()
        let half = Self.span * 0.6 / 2
        a.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y - half), speed: 300)
        b.line(to: CGPoint(x: Self.centre.x, y: Self.centre.y + half), speed: 300)
        a.hold(0.6); b.hold(0.6)
        Finger.lift([a, b])
        hold(1.5)
    }

    /// Pans to `fraction` of the height and releases at rest — 30 % lands,
    /// 15 % springs back — then lands a finger on the card, holds it half
    /// a second, drags it up by `back` at 300 pt/s and releases at rest.
    func catchRelease(of fraction: CGFloat, back: CGFloat) {
        openDunes()
        var finger = Finger(at: Self.grab)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + 20), speed: 300)
        finger.line(to: CGPoint(x: Self.grab.x, y: Self.grab.y + Self.height * fraction), speed: 300)
        finger.hold(0.6)
        finger.lift()
        var catcher = Finger(at: Self.catchPoint)
        catcher.hold(0.5)
        if back > 0 {
            catcher.line(to: CGPoint(x: Self.catchPoint.x, y: Self.catchPoint.y - back), speed: 300)
            catcher.hold(0.6)
        }
        catcher.lift()
        hold(1.5)
    }

    func testCatchLanding() { catchRelease(of: 0.3, back: 150) }
    func testCatchLandingHold() { catchRelease(of: 0.3, back: 0) }
    func testCatchReturn() { catchRelease(of: 0.15, back: 0) }

    // MARK: Stage 8: the once-over. A pop whose source has left the
    // hierarchy, and a tap on the covered page while the card flies.

    /// Opens Dunes, swipes the pager on `pages` posters — Nimbus, three
    /// along, sits a poster's width past the row's right edge; Quartz, four
    /// along, two and a half — and taps back, for the flight to a source off
    /// the screen or not built at all.
    func zoomPopFarPoster(pages: Int) {
        openDunes()
        for _ in 0..<pages {
            var finger = Finger(at: CGPoint(x: 380, y: 600))
            finger.line(to: CGPoint(x: 60, y: 600), speed: 800)
            finger.lift()
            hold(0.8)
        }
        hold(0.5)
        backButton.tap()
        hold(1.5)
    }

    func testZoomPopFarPoster() { zoomPopFarPoster(pages: 3) }
    func testZoomPopFarthestPoster() { zoomPopFarPoster(pages: 4) }

    /// Taps the poster and, as soon as the daemon allows (the card is
    /// then at 0.9 of the screen), taps the first row's left margin beside
    /// it, which the card has not reached; holds, then taps back. If the
    /// tap reached the covered page, the row's page is pushed behind or
    /// after the poster's.
    func testTapCoveredDuringPush() {
        var tap = Finger(at: CGPoint(x: 208, y: 340))
        tap.hold(0.042)
        tap.lift()
        var beside = Finger(at: CGPoint(x: 5, y: 129))
        beside.hold(0.042)
        beside.lift()
        hold(1.2)
        backButton.tap()
        hold(1.5)
    }

    // MARK: Stage 9: how fast a landing is, against how fast the card was
    // moving when the finger left it. The same release point in each
    // gesture at three rates — the 800 pt/s cases are stage 5's and 6's
    // (`testZoomEdge40Fling`, `testZoomPinch45Fast`, `testZoomPinch45Medium`).

    func testZoomEdge40Fling400() { zoomEdgeSwipe(to: 0.4, speed: 400, rest: false) }
    func testZoomEdge40Fling1200() { zoomEdgeSwipe(to: 0.4, speed: 1200, rest: false) }
    func testZoomPinch45Fling1200() { zoomPinch(to: 0.45, speed: 1200, rest: false) }

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
