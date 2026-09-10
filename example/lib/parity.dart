import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Launch-environment switches shared with the native reference app, so
/// the parity driver (docs/parity-plan.md) configures both the same way:
/// `PARITY_SHOW_TOUCHES` draws a ring under every pointer and
/// `PARITY_FLAT` swaps the poster gradients for flat colour. Dart cannot
/// read the launch environment on iOS, so the Runner hands it over.
abstract final class Parity {
  static const MethodChannel _channel = MethodChannel(
    'swift_transitions.example/parity',
  );

  /// Whether to draw a ring under every pointer.
  static bool showTouches = false;

  /// Whether to draw the posters and pages in flat colour.
  static bool flat = false;

  /// Reads the switches from the launch environment.
  static Future<void> load() async {
    var environment = Platform.environment;
    if (Platform.isIOS) {
      try {
        final handed = await _channel.invokeMapMethod<String, String>(
          'environment',
        );
        if (handed != null) {
          environment = handed;
        }
      } on MissingPluginException {
        // Not running in the example's own Runner.
      }
    }
    showTouches = environment['PARITY_SHOW_TOUCHES'] == '1';
    flat = environment['PARITY_FLAT'] == '1';
  }
}

/// Draws a ring under every pointer, above the app, so a recording of a
/// gesture carries the finger's position. A [Listener] in the tree above
/// the navigator sees every pointer without taking part in any arena.
class TouchRings extends StatefulWidget {
  /// Creates the overlay.
  const TouchRings({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  State<TouchRings> createState() => _TouchRingsState();
}

class _TouchRingsState extends State<TouchRings> {
  final Map<int, Offset> _pointers = <int, Offset>{};

  void _update(PointerEvent event) {
    setState(() {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _pointers.remove(event.pointer);
      } else {
        _pointers[event.pointer] = event.position;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _update,
      onPointerMove: _update,
      onPointerUp: _update,
      onPointerCancel: _update,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          widget.child,
          for (final position in _pointers.values)
            Positioned(
              left: position.dx - 12,
              top: position.dy - 12,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xFF33FF33), width: 3),
                    ),
                  ),
                  child: SizedBox(width: 24, height: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
