import 'package:flutter/material.dart';

class BodyContainer extends StatelessWidget {
  final Widget? child;
  final double? width;

  const BodyContainer({super.key, this.child, this.width});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(width: width ?? 640, child: child),
    );
  }
}
