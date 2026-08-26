import 'package:flutter/material.dart';

/// Centers [child] and caps its width — without this, content stretches
/// edge-to-edge on a wide desktop browser window (Flutter web has no
/// built-in phone-width constraint the way a real device does).
/// [maxWidth] defaults to a comfortable phone-ish reading width.
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
