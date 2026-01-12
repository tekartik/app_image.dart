import 'package:flutter/material.dart';

/// Horizontal tile padding.
const horizontalTilePadding = EdgeInsets.symmetric(horizontal: 16);

/// Horizontal padding
class BodyHPadding extends StatelessWidget {
  /// The child widget.
  final Widget? child;

  /// Body horizontal padding constructor.
  const BodyHPadding({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: horizontalTilePadding, child: child);
  }
}
