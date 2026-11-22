import 'package:flutter/material.dart';

import '../../state/location_controller.dart';
import '../common/confirm_dialog.dart';

/// What a my-location button does when tapped (PLAN.md D22). Used by the
/// world map and the location picker, so both behave the same.
///
/// * Location on: nothing to do.
/// * Not allowed yet: shows the OS permission dialog.
/// * Blocked, or location switched off: explains, and offers to open the
///   settings page that can fix it.
///
/// Returns the status afterwards; [LocationStatus.on] means the caller can
/// use the position.
Future<LocationStatus> ensureLocationAccess(
  BuildContext context,
  LocationController location,
) async {
  switch (location.status) {
    case LocationStatus.on:
      return LocationStatus.on;
    case LocationStatus.unknown:
    case LocationStatus.denied:
      return location.requestAccess();
    case LocationStatus.deniedForever:
      await _offerSettings(
        context,
        location,
        title: 'Location access is blocked',
        message: 'To see where you are on the map, allow location access '
            'for QuestMark in your phone\'s settings.',
      );
    case LocationStatus.serviceOff:
      await _offerSettings(
        context,
        location,
        title: 'Location is turned off',
        message: 'Turn on your phone\'s location to see where you are on '
            'the map.',
      );
  }
  return location.status;
}

Future<void> _offerSettings(
  BuildContext context,
  LocationController location, {
  required String title,
  required String message,
}) async {
  final open = await confirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: 'Open settings',
    cancelLabel: 'Cancel',
  );
  if (open) await location.openSettings();
}
