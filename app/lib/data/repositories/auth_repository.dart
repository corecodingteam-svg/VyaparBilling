import '../../core/api_client.dart';
import '../models/app_user.dart';

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  /// Returns the signed-in user if a saved token is still valid; clears it otherwise.
  Future<AppUser?> restore() async {
    if (await _api.tokens.read() == null) return null;
    try {
      return AppUser.fromJson(await _api.get<Map<String, dynamic>>('/auth/me'));
    } catch (_) {
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
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword({required String current, required String next}) =>
      _api.post<dynamic>('/auth/change-password', {'currentPassword': current, 'newPassword': next});

  Future<void> logout() => _api.tokens.clear();

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
