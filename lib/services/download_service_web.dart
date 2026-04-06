import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  await Future<void>.delayed(const Duration(seconds: 2));
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

Future<void> downloadPdfBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  await downloadFileBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: 'application/pdf',
  );
}
