import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../models.dart';

/// A Bloub blob (real SVG frame exported from the Bloub engine)
/// animated in Flutter according to what the advisor is doing.
class BlobAvatar extends StatefulWidget {
  const BlobAvatar({
    super.key,
    required this.advisor,
    this.mood = BlobMood.idle,
    this.size = 40,
  });

  final Advisor advisor;
  final BlobMood mood;
  final double size;

  @override
  State<BlobAvatar> createState() => _BlobAvatarState();
}

class _BlobAvatarState extends State<BlobAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void didUpdateWidget(BlobAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      // Faster loop for speaking/agree, slow for idle/disagree.
      final ms = switch (widget.mood) {
        BlobMood.speaking => 500,
        BlobMood.agree => 600,
        BlobMood.disagree => 2000,
        BlobMood.thinking || BlobMood.confused => 1600,
        _ => 2400,
      };
      _ctrl.duration = Duration(milliseconds: ms);
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = SvgPicture.asset(
      widget.advisor.asset,
      width: widget.size,
      height: widget.size,
    );
    final animated = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value * 2 * math.pi;
        double dx = 0, dy = 0, rot = 0, scale = 1, scaleY = 1;
        switch (widget.mood) {
          case BlobMood.idle:
            scale = 1 + 0.02 * math.sin(t);
          case BlobMood.thinking:
            rot = 0.05 * math.sin(t);
            dy = -1.5 * math.sin(t);
          case BlobMood.speaking:
            dy = -5 * (math.sin(t).abs());
            scaleY = 1 + 0.04 * math.sin(t);
          case BlobMood.agree:
            dy = -7 * (math.sin(t).abs());
            scaleY = 1 - 0.05 * (math.sin(t).abs());
            scale = 1 + 0.03 * (math.sin(t).abs());
          case BlobMood.disagree:
            dx = 2.5 * math.sin(t);
          case BlobMood.confused:
            rot = 0.14 + 0.04 * math.sin(t);
            dy = -1 * math.sin(t);
          case BlobMood.verdict:
            scale = 1 + 0.06 * math.sin(t);
        }
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByVector3(Vector3(dx, dy, 0))
            ..rotateZ(rot)
            ..scaleByVector3(Vector3(scale, scaleY, 1)),
          child: child,
        );
      },
      child: blob,
    );

    // Speaking gets a soft pulsing ring, like a live mic.
    if (widget.mood == BlobMood.speaking) {
      return Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final p = _ctrl.value;
              return Container(
                width: widget.size * (1.1 + 0.15 * p),
                height: widget.size * (1.1 + 0.15 * p),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.advisor.color.withValues(
                      alpha: 0.6 * (1 - p),
                    ),
                    width: 2,
                  ),
                ),
              );
            },
          ),
          animated,
        ],
      );
    }
    return animated;
  }
}

/// The Chairman: black circle, gold gavel — not a blob.
class ChairmanAvatar extends StatelessWidget {
  const ChairmanAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0C),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.gavel,
        color: const Color(0xFFF0B429),
        size: size * 0.55,
      ),
    );
  }
}
