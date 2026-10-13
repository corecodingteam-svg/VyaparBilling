import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Small text storage that survives restarts: the browser's local storage on the web, preferences on a phone or desktop.
abstract class KeyValueStore {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  List<String> keys();
}

class MemoryStore implements KeyValueStore {
  final _data = <String, String>{};
  @override
  String? read(String key) => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> remove(String key) async => _data.remove(key);
  @override
  List<String> keys() => _data.keys.toList();
}

class PrefsStore implements KeyValueStore {
  PrefsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsStore> open() async => PrefsStore(await SharedPreferences.getInstance());

  @override
  String? read(String key) => _prefs.getString(key);
  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> remove(String key) => _prefs.remove(key);
  @override
  List<String> keys() => _prefs.getKeys().toList();
}

/// A random key for a save, so the server can recognise it if it arrives twice.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// The company a login token is for (read from the token itself, not verified — it only decides which cache to use).
String? scopeOfToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    return '${json['firmId']}';
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- reading without a connection

/// The last answer the server gave to each read, so screens still show something when the connection is gone.
/// It is kept per company, bounded in size, and cleared at sign-out.
class ResponseCache {
  ResponseCache(this._store, {this.maxEntries = 120, this.maxEntryBytes = 300000});
  final KeyValueStore _store;
  final int maxEntries;
  final int maxEntryBytes;

  static const _index = 'rc-index';

  /// Reads that must always be live, or are too big or too private to keep.
  static const _never = ['/auth', '/backup', '/integrations', '/files', '/messages', '/einvoice', '/tax-statements/statement', '/google-profile', '/online-payments', '/utilities/backup'];

  static bool cacheable(String path) => !_never.any(path.startsWith);

  String _key(String scope, String path, Map<String, dynamic>? query) {
    final q = (query ?? const {}).entries.where((e) => e.value != null).toList()..sort((a, b) => a.key.compareTo(b.key));
    return 'rc|$scope|$path${q.isEmpty ? '' : '?${q.map((e) => '${e.key}=${e.value}').join('&')}'}';
  }

  List<String> _keys() {
    try {
      return (jsonDecode(_store.read(_index) ?? '[]') as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> put(String scope, String path, Map<String, dynamic>? query, Object? data) async {
    if (!cacheable(path) || data == null) return;
    final text = jsonEncode(data);
    if (text.length > maxEntryBytes) return;
    final key = _key(scope, path, query);
    final keys = _keys()..remove(key);
    keys.add(key);
    try {
      await _write(key, text, keys);
    } catch (_) {
      // Out of room (local storage is small): drop the oldest quarter and try once more.
      try {
        final drop = keys.take(max(1, keys.length ~/ 4)).toList();
        for (final k in drop) {
          await _store.remove(k);
          keys.remove(k);
        }
        await _write(key, text, keys);
      } catch (_) {
        // Caching is a convenience; never fail a request because of it.
      }
    }
  }

  Future<void> _write(String key, String text, List<String> keys) async {
    while (keys.length > maxEntries) {
      await _store.remove(keys.removeAt(0));
    }
    await _store.write(key, text);
    await _store.write(_index, jsonEncode(keys));
  }

  Object? get(String scope, String path, Map<String, dynamic>? query) {
    final text = _store.read(_key(scope, path, query));
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    for (final k in _keys()) {
      await _store.remove(k);
    }
    await _store.remove(_index);
  }

  /// After a save made without a connection, the next document number is one more than the one just used,
  /// so a second offline save does not reuse it.
  Future<void> bumpNumber(String scope, String path, Map<String, dynamic>? query, String used) async {
    final m = RegExp(r'^(.*?)(\d+)$').firstMatch(used);
    if (m == null) return;
    final next = '${m[1]}${(int.parse(m[2]!) + 1).toString().padLeft(m[2]!.length, '0')}';
    await put(scope, path, query, {'number': next});
  }
}

// ---------------------------------------------------------------- saving without a connection

/// A save made while offline, waiting to be sent.
class PendingSave {
  PendingSave({required this.id, required this.scope, required this.method, required this.path, required this.body, required this.label, required this.createdAt, this.error, this.attempts = 0});

  factory PendingSave.fromJson(Map<String, dynamic> j) => PendingSave(
    id: j['id'] as String,
    scope: j['scope'] as String,
    method: j['method'] as String,
    path: j['path'] as String,
    body: j['body'],
    label: j['label'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    error: j['error'] as String?,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
  );

  /// Doubles as the idempotency key.
  final String id;
  final String scope;
  final String method;
  final String path;
  final Object? body;

  /// What the user sees, e.g. "Sale invoice 12 · Ravi · ₹1,180".
  final String label;
  final DateTime createdAt;

  /// Why the server refused it, if it did; such a save stays here until the user fixes or discards it.
  final String? error;
  final int attempts;

  bool get failed => error != null;

  PendingSave copyWith({String? error, int? attempts, bool clearError = false}) => PendingSave(
    id: id, scope: scope, method: method, path: path, body: body, label: label, createdAt: createdAt,
    error: clearError ? null : (error ?? this.error), attempts: attempts ?? this.attempts,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'scope': scope, 'method': method, 'path': path, 'body': body, 'label': label, 'createdAt': createdAt.toIso8601String(), 'error': error, 'attempts': attempts,
  };
}

/// The saves waiting to be sent, in the order they were made.
class SyncQueue {
  SyncQueue(this._store);
  final KeyValueStore _store;
  static const _key = 'sync-queue';

  List<PendingSave> all() {
    try {
      return [for (final j in jsonDecode(_store.read(_key) ?? '[]') as List) PendingSave.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  List<PendingSave> forScope(String scope) => [for (final p in all()) if (p.scope == scope) p];

  Future<void> _save(List<PendingSave> items) => _store.write(_key, jsonEncode([for (final p in items) p.toJson()]));

  Future<void> add(PendingSave p) => _save([...all(), p]);

  Future<void> remove(String id) => _save([for (final p in all()) if (p.id != id) p]);

  Future<void> update(PendingSave p) => _save([for (final x in all()) x.id == p.id ? p : x]);
}
