import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/api_client.dart';
import '../data/repositories/files_repository.dart';

/// Saves [content] as a CSV the user can keep: a download in the browser, a save dialog elsewhere.
/// A UTF-8 byte-order mark is added so spreadsheet apps read ₹ and non-English names correctly.
Future<void> saveTextFile(String fileName, String content) async {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
  await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'text/csv');
}

/// Lets the user pick a CSV file and returns its text, or null if they cancelled.
Future<String?> pickCsvFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
  if (file == null) return null;
  final text = utf8.decode(await file.xFile.readAsBytes(), allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// A file chosen for upload.
typedef PickedUpload = ({String name, String mimeType, Uint8List bytes});

/// Lets the user pick an image (or, with [allowPdf], a PDF) to upload. Returns null if they
/// cancelled; throws a readable message when the file is of another type or too large.
Future<PickedUpload?> pickUpload({bool allowPdf = false}) async {
  final types = {...uploadMimeTypes}..removeWhere((ext, _) => !allowPdf && ext == 'pdf');
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: types.keys.toList());
  if (file == null) return null;
  final name = file.name;
  final mime = types[name.split('.').last.toLowerCase()];
  if (mime == null) throw ApiException('Choose a ${allowPdf ? 'PNG, JPEG, WebP or PDF' : 'PNG, JPEG or WebP'} file.');
  final bytes = await file.xFile.readAsBytes();
  if (bytes.length > maxUploadBytes) throw ApiException('Files can be at most 5 MB.');
  return (name: name, mimeType: mime, bytes: bytes);
}

/// Saves [bytes] under [fileName]: a download in the browser, a save dialog elsewhere.
Future<void> saveBytesFile(String fileName, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
  await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
}

/// Lets the user pick a JSON file (a backup) and returns its text, or null if they cancelled.
Future<String?> pickJsonFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (file == null) return null;
  return utf8.decode(await file.xFile.readAsBytes(), allowMalformed: true);
}
