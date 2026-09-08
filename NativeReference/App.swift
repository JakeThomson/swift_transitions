import SwiftUI
import UIKit

/// Launch-environment switches shared with the Flutter example
/// (`PARITY_SHOW_TOUCHES`, `PARITY_FLAT`), so one driver configures both.
enum Parity {
    static let showTouches = ProcessInfo.processInfo.environment["PARITY_SHOW_TOUCHES"] == "1"
    static let flat = ProcessInfo.processInfo.environment["PARITY_FLAT"] == "1"
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// Owns the window so it can be a `TouchWindow`, which draws a ring under
/// every finger when `PARITY_SHOW_TOUCHES` is set.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = TouchWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: GalleryView())
        self.window = window
        window.makeKeyAndVisible()
    }
}

/// A window that mirrors its touches into ring views above everything,
/// so a recording of a human gesture carries the finger's position.
final class TouchWindow: UIWindow {
    private var rings: [ObjectIdentifier: UIView] = [:]
    private lazy var overlay: UIView = {
        let view = UIView(frame: bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        return view
    }()

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        guard Parity.showTouches, let touches = event.allTouches else { return }
        if overlay.superview == nil { addSubview(overlay) }
        bringSubviewToFront(overlay)
        for touch in touches {
            let key = ObjectIdentifier(touch)
            switch touch.phase {
            case .began, .moved, .stationary:
                let ring = rings[key] ?? makeRing(key)
                ring.center = touch.location(in: overlay)
            default:
                rings[key]?.removeFromSuperview()
                rings[key] = nil
            }
        }
    }

    private func makeRing(_ key: ObjectIdentifier) -> UIView {
        let ring = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        ring.layer.cornerRadius = 12
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor(red: 0.2, green: 1, blue: 0.2, alpha: 1).cgColor
        ring.backgroundColor = .clear
        ring.isUserInteractionEnabled = false
        overlay.addSubview(ring)
        rings[key] = ring
        return ring
    }
}
