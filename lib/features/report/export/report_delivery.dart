/// Getting a finished report off the app: share it, save it, or print it.
///
/// Behind a small class so tests can swap in a fake, since the real ones open system sheets.
/// Everything here happens only after the user has confirmed the export (see the consent dialog
/// on the report screen); nothing is sent anywhere by the app itself.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// The kinds of file a report can be exported as.
enum ExportFormat {
  pdf('application/pdf', 'pdf'),
  csv('text/csv', 'csv'),
  json('application/json', 'json');

  const ExportFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

/// How a file leaves the app.
class ReportDelivery {
  const ReportDelivery();

  /// Opens the system share sheet with the file. True once the sheet has been shown.
  Future<bool> share({
    required String fileName,
    required Uint8List bytes,
    required ExportFormat format,
    String? subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: format.mimeType)],
        subject: subject,
      ),
    );
    return true;
  }

  /// Lets the user choose where to keep the file, through the system file dialog (the Storage
  /// Access Framework on Android, the Files app on iOS). True if it was saved, false if the
  /// user backed out.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required ExportFormat format,
  }) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: format.mimeType,
    );
    return saved != null;
  }

  /// Opens the system print dialog for the PDF.
  Future<bool> printPdf({required String fileName, required Uint8List bytes}) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
}

final reportDeliveryProvider = Provider<ReportDelivery>(
  (ref) => const ReportDelivery(),
);
