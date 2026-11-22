import 'package:flutter/material.dart';

/// How long an "Undo" snackbar stays on screen (user decision).
const undoSnackBarDuration = Duration(seconds: 4);

/// A snackbar with an "Undo" button that disappears by itself after
/// [undoSnackBarDuration].
///
/// Flutter keeps a snackbar that has an action on screen until it's tapped
/// (`SnackBar.persist` defaults to true when there's an action), which
/// left it covering the "New quest" button indefinitely. `persist: false`
/// restores the timeout. Every Undo snackbar in the app uses this, so they
/// all behave the same.
SnackBar undoSnackBar({
  required String message,
  required VoidCallback onUndo,
}) {
  return SnackBar(
    content: Text(message),
    duration: undoSnackBarDuration,
    persist: false,
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
  );
}
