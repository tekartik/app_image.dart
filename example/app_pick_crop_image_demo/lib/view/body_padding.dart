import 'package:flutter/material.dart';

const horizontalTilePadding = EdgeInsets.symmetric(horizontal: 16);

/// Horizontal padding
class BodyHPadding extends StatelessWidget {
  final Widget? child;

  const BodyHPadding({super.key, this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: horizontalTilePadding, child: child);
  }
}
