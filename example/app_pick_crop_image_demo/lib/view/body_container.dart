import 'package:flutter/material.dart';

class BodyContainer extends StatelessWidget {
  final Widget? child;
  final double? width;

  const BodyContainer({Key? key, this.child, this.width}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
        child: SizedBox(
      width: width ?? 640,
      child: child,
    ));
  }
}
