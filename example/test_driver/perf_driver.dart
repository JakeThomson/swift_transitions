import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes each timeline `integration_test/perf_test.dart` reports as a
/// `<key>.timeline_summary.json` under `build/perf` (or `$PERF_OUT`). Keys
/// that differ only by a `#n` suffix are one scenario run several times,
/// and their events are merged into one summary.
Future<void> main() => integrationDriver(
  responseDataCallback: (Map<String, dynamic>? data) async {
    if (data == null) {
      return;
    }
    final destination = Platform.environment['PERF_OUT'] ?? 'build/perf';
    final events = <String, List<dynamic>>{};
    for (final MapEntry<String, dynamic> entry in data.entries) {
      final key = entry.key.split('#').first;
      final timeline = entry.value as Map<String, dynamic>;
      events
          .putIfAbsent(key, () => <dynamic>[])
          .addAll(timeline['traceEvents'] as List<dynamic>);
    }
    for (final MapEntry<String, List<dynamic>> entry in events.entries) {
      final timeline = driver.Timeline.fromJson(<String, dynamic>{
        'traceEvents': entry.value,
      });
      await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(
        entry.key,
        destinationDirectory: destination,
        pretty: true,
        includeSummary: true,
      );
    }
  },
);
