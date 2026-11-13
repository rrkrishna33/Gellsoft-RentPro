import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ids.dart';

/// Takes and keeps the photos of items on a booking. Photos are saved in the
/// app's own folder (not the phone gallery), so nobody else's app sees them.
class PhotoStore {
  /// Replaced in tests so no camera opens: returns the path of a file to use,
  /// or null when the user cancels.
  @visibleForTesting
  static Future<String?> Function(bool camera)? picker;

  /// Replaced in tests: returns the files picked from the gallery.
  @visibleForTesting
  static Future<List<String>> Function()? manyPicker;

  /// Where photos are kept; tests point it at a temporary folder.
  @visibleForTesting
  static Directory? folderOverride;

  static Future<Directory> folder() async {
    final base =
        folderOverride ??
        Directory(p.join((await getApplicationDocumentsDirectory()).path, 'booking_photos'));
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  /// Asks for a photo (camera, or the gallery when [camera] is false) and
  /// copies it into the app's folder. Returns the saved path, or null when the
  /// user cancelled.
  static Future<String?> take({bool camera = true}) async {
    final hook = picker;
    final String? source;
    if (hook != null) {
      source = await hook(camera);
    } else {
      final shot = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        // big enough to see a stain, small enough to keep many on the phone
        maxWidth: 1600,
        imageQuality: 80,
      );
      source = shot?.path;
    }
    if (source == null) return null;
    final dir = await folder();
    final ext = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
    final dest = p.join(dir.path, '${newUuid()}$ext');
    await File(source).copy(dest);
    return dest;
  }

  /// The full path of a saved file, from its name.
  static Future<String> pathOf(String name) async =>
      p.join((await folder()).path, name);

  /// Asks for a picture from the gallery to use as the shop's logo, keeps a
  /// copy in the app's folder and returns its file name (not the path).
  /// Null when the user cancels.
  static Future<String?> pickLogo() async {
    final hook = picker;
    final String? source;
    if (hook != null) {
      source = await hook(false);
    } else {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 700,
        maxHeight: 700,
        imageQuality: 90,
      );
      source = shot?.path;
    }
    if (source == null) return null;
    final dir = await folder();
    final ext = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
    final name = '${newUuid()}$ext';
    await File(source).copy(p.join(dir.path, name));
    return name;
  }

  /// Several pictures at once from the gallery (the person ticks as many as
  /// they like). [limit] stops the picker at that many when it is known.
  /// Each is copied into the app's folder; returns the saved paths, empty
  /// when the user cancels.
  static Future<List<String>> takeMany({int? limit}) async {
    final hook = manyPicker;
    final List<String> sources;
    if (hook != null) {
      sources = await hook();
    } else {
      final shots = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        imageQuality: 80,
        limit: limit != null && limit >= 2 ? limit : null,
      );
      sources = [for (final s in shots) s.path];
    }
    final dir = await folder();
    final saved = <String>[];
    for (final source in sources) {
      final ext = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
      final dest = p.join(dir.path, '${newUuid()}$ext');
      await File(source).copy(dest);
      saved.add(dest);
    }
    return saved;
  }

  /// Deletes a saved photo file. A file that is already gone is fine.
  static Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // nothing to do: the entry is removed from the booking anyway
    }
  }
}
