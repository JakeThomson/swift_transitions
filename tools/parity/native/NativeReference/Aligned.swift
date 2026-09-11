import SwiftUI
import UIKit

/// The aligned zoom, which SwiftUI cannot express: `alignmentRectProvider`
/// is UIKit's alone. Reached with `PARITY_UIKIT=1`, this scene is the
/// gallery again as a UIKit navigation stack, with the example's still row
/// under the posters. A still's page keeps its art under a title and a
/// paragraph, and its zoom aligns the still to the art.
///
/// Laid out by hand at the example's points on the iPhone 17: rows 44 pt
/// from y = 107, posters 120×180 from (16, 250), stills 160×90 from
/// (16, 507); on the page, the art at `StillViewController.artFrame`.
final class AlignedGalleryViewController: UIViewController {
    private var stillViews: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "swift_transitions"
        view.backgroundColor = .white
        navigationItem.backButtonDisplayMode = .minimal

        var y: CGFloat = 107
        for text in ["Push — leading edge back swipe", "Push — back swipe anywhere"] {
            view.addSubview(row(text, y: y))
            y += 44
        }
        view.addSubview(header("Zoom — tap a poster", y: 195))
        view.addSubview(artRow(y: 238, size: CGSize(width: 120, height: 180), radius: 12, taps: false))
        view.addSubview(header("Zoom — tap a still, aligned to its art", y: 442))
        view.addSubview(artRow(y: 495, size: CGSize(width: 160, height: 90), radius: 10, taps: true))
    }

    private func row(_ text: String, y: CGFloat) -> UIView {
        let row = UIView(frame: CGRect(x: 0, y: y, width: 402, height: 44))
        let label = UILabel(frame: CGRect(x: 20, y: 0, width: 340, height: 44))
        label.text = text
        label.font = .systemFont(ofSize: 17)
        row.addSubview(label)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor(Color(hex: 0xC4C4C6))
        chevron.preferredSymbolConfiguration = .init(pointSize: 14, weight: .semibold)
        chevron.sizeToFit()
        chevron.center = CGPoint(x: 402 - 20 - chevron.bounds.width / 2, y: 22)
        row.addSubview(chevron)
        return row
    }

    private func header(_ text: String, y: CGFloat) -> UIView {
        let band = UIView(frame: CGRect(x: 0, y: y, width: 402, height: 53))
        band.backgroundColor = UIColor(Color(hex: 0xF2F2F7))
        let label = UILabel(frame: CGRect(x: 20, y: 22, width: 362, height: 20))
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        band.addSubview(label)
        return band
    }

    /// A row of the posters' art at [size], the stills opening their pages.
    private func artRow(y: CGFloat, size: CGSize, radius: CGFloat, taps: Bool) -> UIView {
        let row = UIScrollView(frame: CGRect(x: 0, y: y, width: 402, height: size.height + 24))
        row.showsHorizontalScrollIndicator = false
        var x: CGFloat = 16
        for poster in posters {
            let art = ArtView(poster: poster, frame: CGRect(origin: CGPoint(x: x, y: 12), size: size))
            art.layer.cornerRadius = radius
            art.layer.masksToBounds = true
            row.addSubview(art)
            if taps {
                art.isUserInteractionEnabled = true
                art.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openStill(_:))))
                stillViews.append(art)
            }
            x += size.width + 12
        }
        row.contentSize = CGSize(width: x + 4, height: row.bounds.height)
        return row
    }

    @objc private func openStill(_ tap: UITapGestureRecognizer) {
        guard let still = tap.view as? ArtView else { return }
        navigationController?.pushViewController(StillViewController(poster: still.poster, source: still), animated: true)
    }
}

/// A poster's artwork as a view: the gradient (or flat colour) and title.
final class ArtView: UIView {
    let poster: Poster
    private let gradient = CAGradientLayer()

    init(poster: Poster, frame: CGRect) {
        self.poster = poster
        super.init(frame: frame)
        if Parity.flat {
            backgroundColor = UIColor(poster.color)
        } else {
            gradient.colors = [UIColor(poster.color).cgColor, UIColor(poster.color.darkened).cgColor]
            layer.addSublayer(gradient)
            let label = UILabel()
            label.text = poster.title
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

/// The page a still zooms open into: title, paragraph, art, paragraph — the
/// example's `StillPage` — with the zoom aligned to the art.
final class StillViewController: UIViewController {
    /// Where the example lays the art out on the iPhone 17, measured from
    /// the Flutter run at rest (stage 3, aligned).
    static let artFrame = CGRect(x: 16, y: 287.333, width: 370, height: 208.125)

    /// The art in another aspect, for the mismatch case (`PARITY_ART_4_3`):
    /// a 4:3 art on the page while the still stays 16:9.
    static var art: CGRect {
        ProcessInfo.processInfo.environment["PARITY_ART_4_3"] == "1"
            ? CGRect(x: 16, y: 287.333, width: 370, height: 277.5)
            : artFrame
    }

    let poster: Poster
    private let art: ArtView

    init(poster: Poster, source: UIView) {
        self.poster = poster
        art = ArtView(poster: poster, frame: Self.art)
        super.init(nibName: nil, bundle: nil)
        title = poster.title
        var options = UIViewController.Transition.ZoomOptions()
        options.alignmentRectProvider = { [art] context in
            art.convert(art.bounds, to: context.zoomedViewController.view)
        }
        preferredTransition = .zoom(options: options) { _ in source }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let scroll = UIScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Frames are in the view's own coordinates, bar strip included, as
        // the example's are; the bar's inset would push them down by it.
        scroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(scroll)

        let titleLabel = UILabel(frame: CGRect(x: 16, y: 125, width: 370, height: 41))
        titleLabel.text = poster.title
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        scroll.addSubview(titleLabel)

        let lead = paragraph(
            "The still is a preview of this art, not of this page: the title and this paragraph come first. The route aligns the flight to the art instead, so the card grows out of the still showing it and shrinks back onto it.",
            y: 174
        )
        scroll.addSubview(lead)

        art.layer.cornerRadius = 12
        art.layer.masksToBounds = true
        scroll.addSubview(art)

        let tail = paragraph(
            "Drag down, swipe in from the leading edge, or pinch to shrink the page into its still. Tap back to zoom home.",
            y: Self.art.maxY + 16
        )
        scroll.addSubview(tail)
        scroll.contentSize = CGSize(width: 402, height: tail.frame.maxY + 16)
    }

    private func paragraph(_ text: String, y: CGFloat) -> UILabel {
        let label = UILabel(frame: CGRect(x: 16, y: y, width: 370, height: 0))
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = 0
        label.sizeToFit()
        label.frame.size.width = 370
        return label
    }
}
