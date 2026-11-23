import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:questmark/ui/offline/region_texts.dart';

import '../../helpers/fake_offline_maps.dart';

void main() {
  test('the estimate: width, tiles and a size range capped at 50 MB', () {
    final plan = RegionPlan(GeoPoint(56.462, -2.971), RegionSize.medium);
    final text = regionEstimate(plan);
    expect(text, startsWith('≈ 39 km across · 1,1'));
    expect(text, endsWith('–50 MB'));
  });

  test('a status line for every state', () {
    expect(regionStatusText(region(1)), 'Ready offline');
    expect(
        regionStatusText(region(1,
            status: RegionStatus.limitReached, coveredRadius: 6)),
        'Ready offline: the middle 18 km. Stopped at OpenFreeMap\'s 50 MB '
        'limit');
    expect(regionStatusText(region(1, status: RegionStatus.paused)), 'Paused');
    expect(
        regionStatusText(region(1,
            status: RegionStatus.paused, problem: RegionProblem.server)),
        'Paused: the map server isn\'t answering');
    expect(
        regionStatusText(region(1,
            status: RegionStatus.paused,
            problem: RegionProblem.interrupted)),
        'Paused: the app was closed');
    expect(regionStatusText(region(1, status: RegionStatus.downloading)),
        'Downloading…');
  });
}
