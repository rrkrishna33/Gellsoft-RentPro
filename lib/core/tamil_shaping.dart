/// The PDF library draws each character in order with no text shaping, but
/// Tamil is written in a different visual order from how it is typed: the
/// vowel signs ெ ே ை appear to the LEFT of their consonant, and ொ ோ ௌ wrap
/// around it. [tamilVisualOrder] rewrites Tamil text into the order it is
/// drawn, so it displays correctly there. Use it for drawing only; keep the
/// original text everywhere else (storage, search, screens).
String tamilVisualOrder(String s) {
  if (!hasTamil(s)) return s;

  bool isConsonant(int r) => r >= 0x0B95 && r <= 0x0BB9;
  final out = <int>[];

  // Put a left-side vowel sign before the consonant it belongs to.
  void before(int sign) {
    if (out.isNotEmpty && isConsonant(out.last)) {
      out.insert(out.length - 1, sign);
    } else {
      out.add(sign);
    }
  }

  for (final r in s.runes) {
    switch (r) {
      case 0x0BC6: // ெ
      case 0x0BC7: // ே
      case 0x0BC8: // ை
        before(r);
      case 0x0BCA: // ொ = ெ + ா
        before(0x0BC6);
        out.add(0x0BBE);
      case 0x0BCB: // ோ = ே + ா
        before(0x0BC7);
        out.add(0x0BBE);
      case 0x0BCC: // ௌ = ெ + ௗ
        before(0x0BC6);
        out.add(0x0BD7);
      default:
        out.add(r);
    }
  }
  return String.fromCharCodes(out);
}

bool hasTamil(String s) => s.runes.any((r) => r >= 0x0B80 && r <= 0x0BFF);
