import 'dart:convert';

import '../../core/api_client.dart';
import '../../core/offline.dart';
import '../models/app_user.dart';

class AuthRepository {
  AuthRepository(this._api, [this._store]);
  final ApiClient _api;

  /// Keeps the last signed-in user so the app can open without a connection.
  final KeyValueStore? _store;
  static const _userKey = 'last-user';

  /// Returns the signed-in user if a saved token is still valid; clears it otherwise.
  /// With no connection the saved token is kept and the user last seen is returned, so a counter can open offline.
  Future<AppUser?> restore() async {
    final token = await _api.tokens.read();
    if (token == null) return null;
    try {
      final json = await _api.get<Map<String, dynamic>>('/auth/me');
      await _store?.write(_userKey, jsonEncode(json));
      return AppUser.fromJson(json);
    } catch (e) {
      if (ApiException.from(e).offline) {
        final saved = _store?.read(_userKey);
        if (saved != null) {
          try {
            final user = AppUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
            if (user.firmId == scopeOfToken(token)) return user;
          } catch (_) {
            // Fall through: nothing usable was saved.
          }
        }
        return null; // not signed out: the token stays for the next start
      }
      await _api.tokens.clear();
      return null;
    }
  }

  Future<AppUser> login({required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email.trim(), 'password': password});

  Future<AppUser> register({
    required String firmName,
    required String stateCode,
    required String fullName,
    required String email,
    required String password,
  }) =>
      _authenticate('/auth/register', {
        'firmName': firmName.trim(),
        'stateCode': stateCode,
        'fullName': fullName.trim(),
        'email': email.trim(),
        'password': password,
      });

  Future<AppUser> _authenticate(String path, Map<String, dynamic> body) async {
    final res = await _api.post<Map<String, dynamic>>(path, body);
    await _api.tokens.write(res['accessToken'] as String);
    await _store?.write(_userKey, jsonEncode(res['user']));
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword({required String current, required String next}) =>
      _api.post<dynamic>('/auth/change-password', {'currentPassword': current, 'newPassword': next});

  Future<void> logout() async {
    await _store?.remove(_userKey);
    await _api.tokens.clear();
  }

  // ---- companies under this login

  Future<List<Company>> companies() async =>
      [for (final j in await _api.get<List<dynamic>>('/firms')) Company.fromJson(j as Map<String, dynamic>)];

  Future<Company> createCompany({required String name, required String stateCode}) async =>
      Company.fromJson(await _api.post<Map<String, dynamic>>('/firms', {'firmName': name.trim(), 'stateCode': stateCode}));

  /// Starts working in another company: the saved token is replaced with one for that company.
  Future<AppUser> switchCompany(String firmId) => _authenticate('/auth/switch-firm', {'firmId': firmId});

  // ---- people in the current company

  Future<List<Member>> members() async => [for (final j in await _api.get<List<dynamic>>('/users')) Member.fromJson(j as Map<String, dynamic>)];

  Future<Member> addMember({required String fullName, required String email, required String password, required String role}) async => Member.fromJson(
        await _api.post<Map<String, dynamic>>('/users', {'fullName': fullName.trim(), 'email': email.trim(), 'password': password, 'role': role}),
      );

  Future<Member> setMemberRole(String userId, String role) async =>
      Member.fromJson(await _api.patch<Map<String, dynamic>>('/users/$userId', {'role': role}));

  Future<void> removeMember(String userId) => _api.delete('/users/$userId');

  /// Deletes a company for good; [name] is its name, typed to confirm.
  Future<void> deleteFirm(String id, String name) => _api.deleteWithBody('/firms/$id', {'name': name});
}
