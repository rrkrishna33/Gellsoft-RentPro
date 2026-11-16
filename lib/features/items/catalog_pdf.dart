import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/pdf_text.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

// The built-in PDF fonts have no rupee glyph, so amounts use "Rs.".
final _num = NumberFormat('#,##0', 'en_IN');
String _rs(double v) => 'Rs. ${_num.format(v)}';

const _accent = PdfColor.fromInt(0xFF1C2C54);
const _ink = PdfColor.fromInt(0xFF1F2937);
const _soft = PdfColor.fromInt(0xFF6B7280);
const _card = PdfColor.fromInt(0xFFF8F2DF);

/// One item of a catalog and the picture to show for it (the cover), if any.
class CatalogEntry {
  const CatalogEntry(this.item, this.photo);
  final RentItem item;
  final Uint8List? photo;
}

/// A catalog of items for a customer to browse: the shop's name at the top,
/// then the items two to a row, each with its picture, name, size and (when
/// [showRates]) rent and deposit. A picture that cannot be read is replaced by
/// a plain box rather than stopping the catalog.
Future<Uint8List> buildCatalogPdf({
  required BusinessProfile shop,
  required List<CatalogEntry> entries,
  required bool showRates,
  Uint8List? logo,
}) async {
  Future<Uint8List> build(bool withPictures) =>
      _catalog(shop, entries, showRates, logo, withPictures);
  try {
    return await build(true);
  } catch (_) {
    // a picture the PDF cannot read: build it again without pictures
    return build(false);
  }
}

Future<Uint8List> _catalog(
  BusinessProfile shop,
  List<CatalogEntry> entries,
  bool showRates,
  Uint8List? logo,
  bool withPictures,
) async {
  final kit = await PdfTextKit.load();
  final doc = pw.Document(theme: kit.theme, title: tr('Catalog'), author: shop.name);
  const margin = 28.0;
  const gap = 12.0;
  final cardWidth = (PdfPageFormat.a4.width - margin * 2 - gap) / 2;

  pw.Widget picture(CatalogEntry e) {
    final bytes = withPictures ? e.photo : null;
    if (bytes != null) {
      try {
        return pw.ClipRRect(
          horizontalRadius: 8,
          verticalRadius: 8,
          child: pw.Image(
            pw.MemoryImage(bytes),
            width: cardWidth - 16,
            height: 170,
            fit: pw.BoxFit.cover,
          ),
        );
      } catch (_) {
        // fall through to the plain box
      }
    }
    return pw.Container(
      width: cardWidth - 16,
      height: 170,
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    );
  }

  pw.Widget card(CatalogEntry e) {
    final i = e.item;
    final sub = [
      if (i.category.isNotEmpty) tr(i.category),
      if (i.size.isNotEmpty) i.size,
    ].join(' - ');
    return pw.Container(
      width: cardWidth,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _card,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          picture(e),
          pw.SizedBox(height: 6),
          kit.text(i.name, size: 11, bold: true, style: const pw.TextStyle(color: _ink)),
          if (sub.isNotEmpty)
            kit.text(sub, size: 8.5, style: const pw.TextStyle(color: _soft)),
          if (showRates) ...[
            pw.SizedBox(height: 3),
            kit.text(
              '${_rs(i.rate)}  (${i.rateType.label})',
              size: 10,
              bold: true,
              style: const pw.TextStyle(color: _accent),
            ),
            if (i.deposit > 0)
              kit.text(
                '${tr('Deposit')}: ${_rs(i.deposit)}',
                size: 8.5,
                style: const pw.TextStyle(color: _soft),
              ),
          ],
        ],
      ),
    );
  }

  pw.Widget header() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      if (logo != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(right: 12),
          child: pw.Image(pw.MemoryImage(logo), height: 44, fit: pw.BoxFit.contain),
        ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            kit.text(shop.name, size: 20, bold: true, style: const pw.TextStyle(color: _accent)),
            if (shop.phone.trim().isNotEmpty)
              kit.text(
                '${tr('Phone')}: ${shop.phone}',
                size: 10,
                style: const pw.TextStyle(color: _soft),
              ),
            if (shop.address.trim().isNotEmpty)
              kit.text(shop.address, size: 9, style: const pw.TextStyle(color: _soft)),
          ],
        ),
      ),
      kit.text(tr('Catalog'), size: 14, bold: true, style: const pw.TextStyle(color: _soft)),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: kit.text(
          '${shop.name}  -  ${c.pageNumber}/${c.pagesCount}',
          size: 8,
          style: const pw.TextStyle(color: _soft),
        ),
      ),
      build: (_) => [
        header(),
        pw.SizedBox(height: 14),
        pw.Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final e in entries) card(e)],
        ),
      ],
    ),
  );
  return doc.save();
}
