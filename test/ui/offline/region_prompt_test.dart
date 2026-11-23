import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:questmark/ui/offline/region_prompt.dart';
import 'package:questmark/ui/offline/region_texts.dart';

void main() {
  final dundee = GeoPoint(56.462, -2.971);

  Future<List<String>> pump(WidgetTester tester,
      {void Function(RegionSize)? onDownload}) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RegionPrompt(
          center: dundee,
          onDownload: (s) {
            log.add('download ${s.name}');
            onDownload?.call(s);
          },
          onNotNow: () => log.add('not now'),
          onNever: () => log.add('never'),
        ),
      ),
    ));
    return log;
  }

  String estimate(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('regionPromptEstimate')))
      .data!;

  testWidgets('asks, with the medium estimate and where the name comes from',
      (tester) async {
    await pump(tester);
    expect(find.text('Download the map for your area?'), findsOneWidget);
    expect(estimate(tester),
        regionEstimate(RegionPlan(dundee, RegionSize.medium)));
    expect(estimate(tester), startsWith('≈ 39 km across · '));
    expect(find.text(regionNameNote), findsOneWidget);
  });

  testWidgets('choosing a size updates the estimate and is what downloads',
      (tester) async {
    final log = await pump(tester);
    await tester.tap(find.byKey(const Key('regionSize-large')));
    await tester.pump();
    expect(estimate(tester),
        regionEstimate(RegionPlan(dundee, RegionSize.large)));
    await tester.tap(find.byKey(const Key('regionPromptDownload')));
    expect(log, ['download large']);
  });

  testWidgets('Not now and Don\'t ask again', (tester) async {
    final log = await pump(tester);
    await tester.tap(find.byKey(const Key('regionPromptNotNow')));
    await tester.tap(find.byKey(const Key('regionPromptNever')));
    expect(log, ['not now', 'never']);
  });
}
