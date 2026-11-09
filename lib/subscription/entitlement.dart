import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this shop has Pro right now. For now this is always false (the
/// Free plan); it is replaced by the license check when billing is wired in,
/// and tests override it.
final isProProvider = Provider<bool>((_) => false);
