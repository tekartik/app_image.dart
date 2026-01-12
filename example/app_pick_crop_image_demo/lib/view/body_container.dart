import 'package:flutter/material.dart';

/// Body container.
class BodyContainer extends StatelessWidget {
  /// Child widget.
  final Widget? child;

  /// Width.
  final double? width;

  /// Body container constructor.
  const BodyContainer({super.key, this.child, this.width});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(width: width ?? 640, child: child),
    );
  }
}
