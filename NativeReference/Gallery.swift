import SwiftUI

/// A poster in the zoom demo's row. Mirrors the Flutter example's `Poster`.
struct Poster: Identifiable, Hashable {
    let title: String
    let color: Color
    var id: String { title }
}

let posters: [Poster] = [
    Poster(title: "Aurora", color: Color(hex: 0x3A7BD5)),
    Poster(title: "Dunes", color: Color(hex: 0xD58B3A)),
    Poster(title: "Kelp", color: Color(hex: 0x2E8B57)),
    Poster(title: "Magma", color: Color(hex: 0xC0392B)),
    Poster(title: "Nimbus", color: Color(hex: 0x6C5CE7)),
    Poster(title: "Quartz", color: Color(hex: 0x8E44AD)),
]

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// `Color.lerp(color, black, 0.45)` from the Flutter example.
    var darkened: Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: r * 0.55, green: g * 0.55, blue: b * 0.55)
    }
}

/// The gallery's home page: two push rows and the poster row.
///
/// Laid out by hand rather than with `List`, so the rows and the poster row
/// sit at the same points as the Flutter example's `CupertinoListTile`s and
/// `CupertinoListSection` (rows 44 pt from y = 107, header 44 pt, posters
/// from y = 250): the parity driver taps by coordinate.
struct GalleryView: View {
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    NavigationLink {
                        PushDemoView(anywhere: false)
                    } label: {
                        GalleryRow(title: "Push — leading edge back swipe")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("push_edge")
                    NavigationLink {
                        PushDemoView(anywhere: true)
                    } label: {
                        GalleryRow(title: "Push — back swipe anywhere")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("push_anywhere")
                    HStack {
                        Text("Zoom — tap a poster")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                    .frame(height: 44)
                    .background(Color(hex: 0xF2F2F7))
                    PosterRow(namespace: zoom)
                        .background(Color.white)
                    Color(hex: 0xF2F2F7).frame(height: 8)
                }
                // The scroll view sits 10 pt lower under the bar than the
                // example's list; measured, not derived.
                .padding(.top, -10)
            }
            .background(Color.white)
            .navigationTitle("swift_transitions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Poster.self) { poster in
                PosterPager(initial: poster, namespace: zoom)
            }
        }
    }
}

/// A 44 pt row with a chevron, the shape of a `CupertinoListTile`.
struct GalleryRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xC4C4C6))
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
}

/// The horizontally scrolling row of posters, each a zoom source.
struct PosterRow: View {
    let namespace: Namespace.ID
    private let height: CGFloat = 180

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(posters) { poster in
                    NavigationLink(value: poster) {
                        PosterArt(poster: poster)
                            .frame(width: 120, height: height)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: poster.id, in: namespace) { source in
                        source.clipShape(.rect(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("poster_\(poster.title)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: height + 24)
    }
}

/// A poster's artwork: a coloured card with its title.
struct PosterArt: View {
    let poster: Poster

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if Parity.flat {
                poster.color
            } else {
                LinearGradient(
                    colors: [poster.color, poster.color.darkened],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            if !Parity.flat {
                Text(poster.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
    }
}

/// The poster pages, swiped through sideways; whichever is showing is the
/// zoom's source on the way back.
struct PosterPager: View {
    let initial: Poster
    let namespace: Namespace.ID
    @State private var current: Poster

    init(initial: Poster, namespace: Namespace.ID) {
        self.initial = initial
        self.namespace = namespace
        _current = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $current) {
            ForEach(posters) { poster in
                PosterPage(poster: poster).tag(poster)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(.zoom(sourceID: current.id, in: namespace))
    }
}

/// The page a poster zooms open into.
struct PosterPage: View {
    let poster: Poster

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PosterArt(poster: poster)
                    .aspectRatio(2 / 3, contentMode: .fit)
                Text(
                    "Drag down from the top of this page, swipe in from the leading edge, or pinch with two fingers to shrink it into its poster; let go early and it springs back, and a card on its way anywhere can be caught. Swipe sideways for the next poster, which is then the one this page lands on. Tap back to zoom home."
                )
                .padding(16)
            }
        }
        .background(Parity.flat ? Color(hex: 0xE0F0FF) : Color.white)
    }
}

/// The pushed page for the push-transition demos.
struct PushDemoView: View {
    let anywhere: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text(anywhere ? "Swipe anywhere on this page to go back." : "Swipe from the leading edge to go back.")
            NavigationLink("Push another") {
                PushDemoView(anywhere: anywhere)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("push_another")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Parity.flat ? Color(hex: 0xD8FFE0) : Color.white)
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
