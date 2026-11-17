import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../theme.dart';

/// The visual states of a quest marker (PLAN.md D9).
enum QuestMarkerKind {
  /// Open quest: golden "!".
  active,

  /// Open and due today or tomorrow: orange "!".
  dueSoon,

  /// Open and its due day has passed: red "!".
  overdue,

  /// Completed: small grey check, no animation.
  done;

  /// Whether the marker bobs up and down to draw attention.
  bool get animates => this != done;

  /// Decides the marker state for [task] at time [now]. Pure, so it can be
  /// unit tested without any widgets.
  static QuestMarkerKind of(Task task, DateTime now) {
    if (task.isDone) return done;
    if (task.isOverdue(now)) return overdue;
    final due = task.dueAt;
    if (due != null) {
      final d = due.toLocal();
      final n = now.toLocal();
      final days = DateTime(d.year, d.month, d.day)
          .difference(DateTime(n.year, n.month, n.day))
          .inDays;
      if (days <= 1) return dueSoon;
    }
    return active;
  }
}

/// Colours per state. Kept apart from the widget so the polish phase can
/// restyle markers in one place.
class QuestMarkerColors {
  const QuestMarkerColors(this.fill, this.glyph);
  final Color fill;
  final Color glyph;

  static QuestMarkerColors of(QuestMarkerKind kind) => switch (kind) {
        QuestMarkerKind.active =>
          const QuestMarkerColors(questGold, Color(0xFF3E2723)),
        QuestMarkerKind.dueSoon =>
          const QuestMarkerColors(Color(0xFFF57C00), Colors.white),
        QuestMarkerKind.overdue =>
          const QuestMarkerColors(Color(0xFFD32F2F), Colors.white),
        QuestMarkerKind.done =>
          const QuestMarkerColors(Color(0xFF9E9E9E), Colors.white),
      };
}

/// A game-style quest marker: a glowing diamond with "!" for open quests,
/// a small grey check for completed ones.
///
/// Open quests bob gently. The animation stops when the system "remove
/// animations" accessibility setting is on, and when the map tab is hidden
/// (HomeShell turns tickers off for the hidden tab), so it costs no
/// battery while you're on the list.
class QuestMarker extends StatefulWidget {
  const QuestMarker({
    super.key,
    required this.task,
    required this.kind,
    this.onTap,
  });

  final Task task;
  final QuestMarkerKind kind;
  final VoidCallback? onTap;

  /// Size of the marker box handed to flutter_map. It includes headroom for
  /// the bobbing motion.
  static const double size = 48;

  @override
  State<QuestMarker> createState() => _QuestMarkerState();
}

class _QuestMarkerState extends State<QuestMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(QuestMarker old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _updateAnimation();
  }

  void _updateAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.kind.animates && !reduceMotion) {
      if (!_bob.isAnimating) _bob.repeat(reverse: true);
    } else {
      _bob
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final colors = QuestMarkerColors.of(kind);

    final Widget shape = kind == QuestMarkerKind.done
        ? _DoneBadge(colors: colors)
        : _QuestDiamond(colors: colors);

    return Semantics(
      button: true,
      label: _semanticLabel(),
      // The "!" / check glyphs are decoration; the label says it all.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedBuilder(
            animation: _bob,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                  0, -4 * Curves.easeInOut.transform(_bob.value)),
              child: child,
            ),
            child: shape,
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final state = switch (widget.kind) {
      QuestMarkerKind.active => 'Quest',
      QuestMarkerKind.dueSoon => 'Quest, due soon',
      QuestMarkerKind.overdue => 'Quest, overdue',
      QuestMarkerKind.done => 'Completed quest',
    };
    return '$state: ${widget.task.title}';
  }
}

class _QuestDiamond extends StatelessWidget {
  const _QuestDiamond({required this.colors});
  final QuestMarkerColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: colors.fill,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  // The "glow" that makes it read as a game marker.
                  BoxShadow(
                    color: colors.fill.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                  const BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          Text(
            '!',
            style: TextStyle(
              color: colors.glyph,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.colors});
  final QuestMarkerColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: colors.fill,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(Icons.check, size: 14, color: colors.glyph),
    );
  }
}
