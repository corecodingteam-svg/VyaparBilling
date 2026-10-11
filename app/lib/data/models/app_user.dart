import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({required this.id, required this.email, required this.fullName, required this.firmId, required this.firmName, this.role = 'owner'});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        firmId: ((json['firm'] as Map)['id'] as String?) ?? '',
        firmName: (json['firm'] as Map)['name'] as String,
        role: (json['role'] as String?) ?? 'owner',
      );

  final String id;
  final String email;
  final String fullName;

  /// The company this session is working in.
  final String firmId;
  final String firmName;

  /// owner | admin | accountant | salesman — in the current company.
  final String role;

  /// Salesmen only bill customers and collect payments; everyone else sees the full books.
  bool get isSalesman => role == 'salesman';
  bool get isAdmin => role == 'owner' || role == 'admin';

  AppUser copyWith({String? firmName}) =>
      AppUser(id: id, email: email, fullName: fullName, firmId: firmId, firmName: firmName ?? this.firmName, role: role);

  @override
  List<Object?> get props => [id, email, fullName, firmId, firmName, role];
}

const roleLabels = {'owner': 'Owner', 'admin': 'Admin', 'accountant': 'Accountant', 'salesman': 'Salesman'};

const roleHints = {
  'admin': 'Everything, including users and company settings.',
  'accountant': 'All transactions, reports and settings. Cannot manage users.',
  'salesman': 'Sale documents, Payment-In, parties and POS only. No purchases, expenses, bank or reports.',
};

/// A company this login can open.
class Company extends Equatable {
  Company.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        role = (j['role'] as String?) ?? 'owner',
        current = (j['current'] as bool?) ?? false;

  final String id;
  final String name;
  final String role;
  final bool current;

  @override
  List<Object?> get props => [id, name, role, current];
}

/// Someone with access to the current company.
class Member extends Equatable {
  Member.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        fullName = j['fullName'] as String,
        email = j['email'] as String,
        role = j['role'] as String;

  final String id;
  final String fullName;
  final String email;
  final String role;

  @override
  List<Object?> get props => [id, fullName, email, role];
}
