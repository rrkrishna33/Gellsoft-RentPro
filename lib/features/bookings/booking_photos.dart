import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../data/photo_store.dart';
import '../../l10n/strings.dart';
import '../../subscription/entitlement.dart';
import '../../subscription/plan.dart';
import '../../subscription/pro_prompt.dart';
import '../common/widgets.dart';

String stageLabel(String stage) => switch (stage) {
  'pickup' => tr('Pickup'),
  'return' => tr('Return'),
  _ => tr('Other'),
};

/// The photos of a booking: thumbnails, an add button, and a viewer.
/// The free plan keeps [FreePlan.photosPerBooking]; Pro keeps any number.
class PhotosSection extends ConsumerWidget {
  const PhotosSection({super.key, required this.booking});
  final Booking booking;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final isPro = ref.read(isProProvider);
    if (!isPro && booking.photos.length >= FreePlan.photosPerBooking) {
      await showProPrompt(context, ProFeature.unlimitedPhotos);
      return;
    }
    final choice = await showModalBottomSheet<(bool, String)>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AddSheet(
        initialStage: switch (booking.status) {
          BookingStatus.pickedUp => 'return',
          BookingStatus.returned => 'return',
          _ => 'pickup',
        },
      ),
    );
    if (choice == null || !context.mounted) return;
    final path = await PhotoStore.take(camera: choice.$1);
    if (path == null) return;
    try {
      await ref
          .read(bookingRepoProvider)
          .addPhoto(booking.id, path: path, stage: choice.$2, isPro: isPro);
    } on BookingException {
      // the free limit was reached while the camera was open
      await PhotoStore.delete(path);
      if (context.mounted) {
        await showProPrompt(context, ProFeature.unlimitedPhotos);
      }
    }
    ref.invalidate(bookingProvider(booking.id));
  }

  Future<void> _view(BuildContext context, WidgetRef ref, BookingPhoto ph) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(ph.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('This photo is no longer on the phone.')),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${stageLabel(ph.stage)} · ${dateText(ph.createdAt)}',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr('Remove')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(tr('Close')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (remove != true || !context.mounted) return;
    final sure = await confirmRemove(
      context,
      title: tr('Remove this photo?'),
      message: tr('The photo is deleted from this phone.'),
    );
    if (!sure) return;
    await ref.read(bookingRepoProvider).removePhoto(ph.id);
    await PhotoStore.delete(ph.path);
    ref.invalidate(bookingProvider(booking.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final photos = booking.photos;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                tr('Photos'),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (!isPro)
                Text(
                  tr('{n} of {max} on the free plan', {
                    'n': photos.length,
                    'max': FreePlan.photosPerBooking,
                  }),
                  style: text.bodySmall,
                ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final ph in photos)
                  GestureDetector(
                    onTap: () => _view(context, ref, ph),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(ph.path),
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 88,
                              height: 88,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              stageLabel(ph.stage),
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                InkWell(
                  onTap: () => _add(context, ref),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_a_photo_outlined),
                        const SizedBox(height: 4),
                        Text(tr('Add photo'), style: text.labelSmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Camera or gallery, and what the photo is of.
class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.initialStage});
  final String initialStage;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  late String _stage = widget.initialStage;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('This photo is of'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in const ['pickup', 'return', 'other'])
                ChoiceChip(
                  label: Text(stageLabel(s)),
                  selected: _stage == s,
                  onSelected: (_) => setState(() => _stage = s),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Take photo')),
            onTap: () => Navigator.pop(context, (true, _stage)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Choose from gallery')),
            onTap: () => Navigator.pop(context, (false, _stage)),
          ),
        ],
      ),
    ),
  );
}
