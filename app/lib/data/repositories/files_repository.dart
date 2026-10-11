import 'dart:convert';
import 'dart:typed_data';

import '../../core/api_client.dart';
import '../models/extras.dart';

/// Uploaded files and the attachments on transactions.
class FilesRepository {
  FilesRepository(this._api);
  final ApiClient _api;
  final _cache = <String, StoredFile>{};

  Future<StoredFile> upload({required String name, required String mimeType, required Uint8List bytes}) async => StoredFile.fromJson(
        await _api.post<Map<String, dynamic>>('/files', {'name': name, 'mimeType': mimeType, 'dataBase64': base64Encode(bytes)}),
      );

  /// The file with its contents. Files never change once uploaded, so they are kept for the session.
  Future<StoredFile> get(String id) async => _cache[id] ??= StoredFile.fromJson(await _api.get<Map<String, dynamic>>('/files/$id'));

  /// Contents of [id], or null when there is none or it cannot be fetched (a missing logo must not break printing).
  Future<Uint8List?> bytesOrNull(String? id) async {
    if (id == null) return null;
    try {
      return (await get(id)).bytes;
    } catch (_) {
      return null;
    }
  }

  List<Attachment> _list(List<dynamic> json) => [for (final j in json) Attachment.fromJson(j as Map<String, dynamic>)];

  Future<List<Attachment>> attachments(String ownerType, String ownerId) async =>
      _list(await _api.get<List<dynamic>>('/attachments', query: {'ownerType': ownerType, 'ownerId': ownerId}));

  Future<List<Attachment>> attach(String ownerType, String ownerId, String fileId) async =>
      _list(await _api.post<List<dynamic>>('/attachments', {'ownerType': ownerType, 'ownerId': ownerId, 'fileId': fileId}));

  Future<void> detach(String attachmentId) => _api.delete('/attachments/$attachmentId');
}

/// Types the server accepts, by file extension.
const uploadMimeTypes = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp', 'pdf': 'application/pdf'};
const maxUploadBytes = 5 * 1024 * 1024;
