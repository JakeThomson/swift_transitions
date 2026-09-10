# swift_transitions example

A runnable gallery for the [`swift_transitions`](https://pub.dev/packages/swift_transitions)
package.

```sh
flutter pub get
flutter run
```

The list at the top pushes with `SwiftPageRoute`, once with the back swipe on
the leading edge and once with it anywhere on the page. The row of posters
below opens with `ZoomPageRoute`: tap a poster to fly its page out of it, then
drag down, swipe in from the leading edge, or pinch with two fingers to send it
back. Let go early and the card springs back; catch it in flight and it follows
the finger. Swiping the page sideways moves to the next poster, which is then
the one the dismissal lands on.

iOS and macOS are the reference platforms, since the transitions are modelled
on iOS. The app also builds for Android and web.
