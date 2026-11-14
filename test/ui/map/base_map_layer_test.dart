import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/base_map_layer.dart';

/// The success path (a real vector style rendering tiles) needs the
/// network and a device, so it's checked manually on a phone. These tests
/// cover the loading and failure behaviour around it.
void main() {
  Future<void> pumpLayer(WidgetTester tester, StyleLoader loader) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OpenFreeMapLayer(loadStyle: loader)),
    ));
  }

  testWidgets('shows nothing while the style is loading', (tester) async {
    final pending = Completer<vt.Style>();
    await pumpLayer(tester, () => pending.future);
    await tester.pump();

    expect(find.byType(MapLoadErrorBanner), findsNothing);
    expect(find.byType(vt.VectorTileLayer), findsNothing);
  });

  testWidgets('a failed load shows the error banner', (tester) async {
    await pumpLayer(tester, () async => throw Exception('offline'));
    await tester.pumpAndSettle();

    expect(find.byType(MapLoadErrorBanner), findsOneWidget);
    expect(find.textContaining("Couldn't load the map"), findsOneWidget);
  });

  testWidgets('Retry loads the style again', (tester) async {
    var calls = 0;
    final second = Completer<vt.Style>();
    await pumpLayer(tester, () {
      calls++;
      return calls == 1 ? Future.error(Exception('offline')) : second.future;
    });
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(calls, 2);
    // While the retry is in flight, the banner is hidden.
    expect(find.byType(MapLoadErrorBanner), findsNothing);
  });
}
