import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Stamps user-supplied field values onto a PDF and returns the filled bytes.
class PdfStamper {
  /// Fills [fieldValues] (AcroForm field name → value) into [originalPdfBytes].
  ///
  /// Text fields receive string values; checkboxes receive `bool` or the
  /// strings `'true'`/`'Yes'`. Signature fields accept PNG bytes (Uint8List)
  /// which are drawn at the field's bounds on the page.
  static Uint8List stamp(
    Uint8List originalPdfBytes,
    Map<String, dynamic> fieldValues,
  ) {
    final document = PdfDocument(inputBytes: originalPdfBytes);
    final form = document.form;

    for (int i = 0; i < form.fields.count; i++) {
      final field = form.fields[i];
      final value = fieldValues[field.name];
      if (value == null) continue;

      try {
        if (field is PdfTextBoxField) {
          field.text = value.toString();
        } else if (field is PdfCheckBoxField) {
          field.isChecked = value == true ||
              value.toString().toLowerCase() == 'true' ||
              value.toString().toLowerCase() == 'yes';
        } else if (field is PdfComboBoxField) {
          final str = value.toString();
          for (int j = 0; j < field.items.count; j++) {
            if (field.items[j].text == str) {
              field.selectedIndex = j;
              break;
            }
          }
        } else if (field is PdfRadioButtonListField) {
          final str = value.toString();
          for (int j = 0; j < field.items.count; j++) {
            if (field.items[j].value == str) {
              field.selectedIndex = j;
              break;
            }
          }
        } else if (field is PdfSignatureField) {
          if (value is Uint8List && value.isNotEmpty) {
            final page = field.page;
            if (page != null) {
              page.graphics.drawImage(PdfBitmap(value), field.bounds);
            }
          }
        }
      } catch (_) {
        // Non-fatal — field may be read-only or already flattened
      }
    }

    final bytes = document.saveSync();
    document.dispose();
    return Uint8List.fromList(bytes);
  }
}
