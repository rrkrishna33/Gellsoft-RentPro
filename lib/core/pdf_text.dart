import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'tamil_shaping.dart';

/// PDF fonts: Helvetica for English, Noto Sans Tamil for Tamil (used
/// automatically for any character Helvetica lacks).
class PdfTextKit {
  PdfTextKit._(this._regular, this._bold);
  final pw.Font _regular, _bold;

  static Future<PdfTextKit>? _loading;

  /// Loads the bundled Tamil fonts once.
  static Future<PdfTextKit> load() => _loading ??= () async {
    Future<pw.Font> font(String file) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
    return PdfTextKit._(
      await font('NotoSansTamil-Regular.ttf'),
      await font('NotoSansTamil-Bold.ttf'),
    );
  }();

  /// Theme for the whole document.
  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
    boldItalic: pw.Font.helveticaBoldOblique(),
    fontFallback: [_regular],
  );

  /// Text for user data (names, addresses, notes) that may be Tamil.
  pw.Text text(
    String s, {
    double? size,
    bool bold = false,
    pw.TextStyle? style,
    pw.TextAlign? align,
    int? maxLines,
  }) {
    var st = style ?? const pw.TextStyle();
    st = st.copyWith(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : null,
      // Bold Latin comes from Helvetica-Bold; bold Tamil needs its own font.
      fontFallback: bold ? [_bold] : null,
    );
    return pw.Text(
      tamilVisualOrder(s),
      style: st,
      textAlign: align,
      maxLines: maxLines,
    );
  }
}
