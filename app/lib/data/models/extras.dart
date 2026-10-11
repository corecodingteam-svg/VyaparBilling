import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// An uploaded file (logo, signature, item image, attachment).
class StoredFile extends Equatable {
  StoredFile.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        mimeType = j['mimeType'] as String,
        size = (j['size'] as num).toInt(),
        bytes = j['dataBase64'] == null ? null : base64Decode(j['dataBase64'] as String);

  final String id;
  final String name;
  final String mimeType;
  final int size;

  /// The contents; only present when the file itself was fetched.
  final Uint8List? bytes;

  bool get isImage => mimeType.startsWith('image/');

  @override
  List<Object?> get props => [id, name, mimeType, size];
}

/// A file attached to an invoice, expense or payment.
class Attachment extends Equatable {
  Attachment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        fileId = j['fileId'] as String,
        name = j['name'] as String,
        mimeType = j['mimeType'] as String,
        size = (j['size'] as num).toInt();

  final String id;
  final String fileId;
  final String name;
  final String mimeType;
  final int size;

  @override
  List<Object?> get props => [id, fileId, name, mimeType, size];
}

/// A customer with overdue invoices.
class PaymentReminder extends Equatable {
  PaymentReminder.fromJson(Map<String, dynamic> j)
      : partyId = j['partyId'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String?,
        balance = j['balance'] as num,
        overdueAmount = j['overdueAmount'] as num,
        invoices = (j['invoices'] as num).toInt(),
        oldestDue = j['oldestDue'] as String,
        daysOverdue = (j['daysOverdue'] as num).toInt();

  final String partyId;
  final String name;
  final String? phone;

  /// Everything the party owes.
  final num balance;
  final num overdueAmount;
  final int invoices;
  final String oldestDue;
  final int daysOverdue;

  @override
  List<Object?> get props => [partyId, name, phone, balance, overdueAmount, invoices, oldestDue, daysOverdue];
}

/// A service sold whose next visit is coming up or overdue.
class ServiceReminder extends Equatable {
  ServiceReminder.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        itemName = j['itemName'] as String,
        invoiceId = j['invoiceId'] as String,
        invoiceNumber = j['invoiceNumber'] as String,
        soldOn = j['soldOn'] as String,
        partyName = j['partyName'] as String,
        phone = j['phone'] as String?,
        dueDate = j['dueDate'] as String,
        daysLeft = (j['daysLeft'] as num).toInt();

  final String id;
  final String itemName;
  final String invoiceId;
  final String invoiceNumber;
  final String soldOn;
  final String partyName;
  final String? phone;
  final String dueDate;

  /// Negative when overdue.
  final int daysLeft;

  @override
  List<Object?> get props => [id, itemName, invoiceId, invoiceNumber, soldOn, partyName, phone, dueDate, daysLeft];
}

/// One row in quick search.
class SearchHit extends Equatable {
  const SearchHit({required this.kind, required this.id, required this.title, this.subtitle = '', this.type});

  /// party | item | invoice
  final String kind;
  final String id;
  final String title;
  final String subtitle;

  /// Documents: the document type ('sale', 'estimate', ...). Items: 'product' or 'service'.
  final String? type;

  @override
  List<Object?> get props => [kind, id, title, subtitle, type];
}

class SetupStep extends Equatable {
  SetupStep.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        hint = j['hint'] as String,
        route = j['route'] as String,
        done = j['done'] as bool;

  final String id;
  final String title;
  final String hint;
  final String route;
  final bool done;

  @override
  List<Object?> get props => [id, title, hint, route, done];
}

class VerifyIssue extends Equatable {
  VerifyIssue.fromJson(Map<String, dynamic> j)
      : label = j['label'] as String,
        detail = j['detail'] as String;
  final String label;
  final String detail;

  @override
  List<Object?> get props => [label, detail];
}

/// One consistency check of the books.
class VerifyCheck extends Equatable {
  VerifyCheck.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        fixable = j['fixable'] as bool,
        issues = [for (final i in j['issues'] as List) VerifyIssue.fromJson(i as Map<String, dynamic>)];

  final String id;
  final String title;

  /// "Fix" can repair it; otherwise the listed transactions need a look.
  final bool fixable;
  final List<VerifyIssue> issues;

  bool get ok => issues.isEmpty;

  @override
  List<Object?> get props => [id, title, fixable, issues];
}
