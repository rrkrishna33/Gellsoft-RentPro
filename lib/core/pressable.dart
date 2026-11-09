import 'package:flutter/material.dart';

/// A tappable box that paints its own decoration (colour, gradient, border,
/// shadow) and puts the ripple on top of it.
///
/// Use this instead of `Ink` when the decoration has a shadow: `Ink` paints on
/// the nearest Material and clips the shadow to a rectangle.
class Pressable extends StatelessWidget {
  const Pressable({
    super.key,
    required this.decoration,
    required this.child,
    this.onTap,
    this.padding,
    this.width,
    this.height,
  });

  final BoxDecoration decoration;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final circle = decoration.shape == BoxShape.circle;
    return Container(
      width: width,
      height: height,
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: circle ? const CircleBorder() : null,
          borderRadius: circle
              ? null
              : (decoration.borderRadius is BorderRadius
                    ? decoration.borderRadius as BorderRadius
                    : null),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}
