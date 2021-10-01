import 'package:flutter/material.dart';

const horizontalTilePadding = EdgeInsets.symmetric(horizontal: 16);

/// Horizontal padding
class BodyHPadding extends StatelessWidget {
  final Widget? child;

  const BodyHPadding({Key? key, this.child}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: horizontalTilePadding,
      child: child,
    );
  }
}
