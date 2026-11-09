import 'package:flutter/widgets.dart';

/// Rebuilds everything below it from scratch (new provider state), used
/// after a backup is restored.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restart(BuildContext context) =>
      context.findAncestorStateOfType<_RestartWidgetState>()?._restart();

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
