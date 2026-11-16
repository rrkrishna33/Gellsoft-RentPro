import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// A small square picture of a saved photo file, or a plain box when the file
/// cannot be read. Decoded at a small size so a long list stays light.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.path, this.size = 56});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => ColoredBox(
            color: scheme.primaryContainer,
            child: Icon(
              Icons.image_not_supported_outlined,
              color: scheme.onPrimaryContainer,
              size: size / 2.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// The pictures of an item as a row: the cover first, each with a button to
/// take it off (and, for the others, to make it the cover), then a tile to add
/// more. [onAdd] is called when the tile is tapped; the screen decides what
/// happens (the picker, or the Pro prompt when the free plan's one picture is
/// used).
class ItemPhotoStrip extends StatelessWidget {
  const ItemPhotoStrip({
    super.key,
    required this.paths,
    required this.canAddMore,
    required this.locked,
    required this.onAdd,
    required this.onRemove,
    required this.onMakeCover,
  });

  /// The pictures, the cover first.
  final List<String> paths;

  /// There is room for another one.
  final bool canAddMore;

  /// The add tile asks for Pro instead (the free plan's picture is used).
  final bool locked;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(int index) onMakeCover;

  static const _side = 92.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: _side,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < paths.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  PhotoThumb(path: paths[i], size: _side),
                  if (i == 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tr('Cover'),
                          style: text.labelSmall?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _Round(
                      icon: Icons.close,
                      tooltip: tr('Remove this picture'),
                      onTap: () => onRemove(i),
                    ),
                  ),
                  if (i > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: _Round(
                        icon: Icons.star_outline,
                        tooltip: tr('Make this the cover'),
                        onTap: () => onMakeCover(i),
                      ),
                    ),
                ],
              ),
            ),
          if (canAddMore || locked)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onAdd,
              child: Container(
                width: _side,
                height: _side,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      locked ? Icons.lock_outline : Icons.add_a_photo_outlined,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked ? tr('More with Pro') : tr('Add picture'),
                      textAlign: TextAlign.center,
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    ),
  );
}
