import 'package:equatable/equatable.dart';

/// One setting of an outside service, as the server describes it. A secret is never sent back:
/// [stored] shows only its last four characters, so the screen can tell it is saved.
class IntegrationField extends Equatable {
  IntegrationField.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      label = j['label'] as String,
      secret = j['secret'] as bool,
      required = j['required'] as bool,
      help = j['help'] as String?,
      options = (j['options'] as List?)?.cast<String>(),
      value = (j['value'] as String?) ?? '',
      stored = j['stored'] as String?;

  final String key;
  final String label;
  final bool secret;
  final bool required;
  final String? help;
  final List<String>? options;
  final String value;
  final String? stored;

  @override
  List<Object?> get props => [key, label, secret, required, help, options, value, stored];
}

class Integration extends Equatable {
  Integration.fromJson(Map<String, dynamic> j)
    : provider = j['provider'] as String,
      title = j['title'] as String,
      help = j['help'] as String,
      connected = j['connected'] as bool,
      fields = [for (final f in j['fields'] as List) IntegrationField.fromJson(f as Map<String, dynamic>)],
      email = (j['info'] as Map<String, dynamic>?)?['email'] as String?,
      location = (j['info'] as Map<String, dynamic>?)?['location'] as String?;

  final String provider;
  final String title;
  final String help;
  final bool connected;
  final List<IntegrationField> fields;

  /// Google Business Profile only: the account it was connected as and the listing being managed.
  final String? email;
  final String? location;

  @override
  List<Object?> get props => [provider, title, help, connected, fields, email, location];
}

class MessageEntry extends Equatable {
  MessageEntry.fromJson(Map<String, dynamic> j)
    : channel = j['channel'] as String,
      kind = j['kind'] as String,
      to = j['to'] as String,
      body = j['body'] as String,
      ok = j['status'] == 'sent',
      error = j['error'] as String?,
      createdAt = DateTime.parse(j['createdAt'] as String).toLocal(),
      partyName = j['partyName'] as String?;

  final String channel;
  final String kind;
  final String to;
  final String body;
  final bool ok;
  final String? error;
  final DateTime createdAt;
  final String? partyName;

  @override
  List<Object?> get props => [channel, kind, to, body, ok, error, createdAt, partyName];
}

class Transport extends Equatable {
  const Transport({this.mode, this.transporterId, this.transporterName, this.docNo, this.docDate, this.vehicleNo, this.distanceKm});

  factory Transport.fromJson(Map<String, dynamic> j) => Transport(
    mode: j['mode'] as String?,
    transporterId: j['transporterId'] as String?,
    transporterName: j['transporterName'] as String?,
    docNo: j['docNo'] as String?,
    docDate: j['docDate'] as String?,
    vehicleNo: j['vehicleNo'] as String?,
    distanceKm: (j['distanceKm'] as num?)?.toInt(),
  );

  final String? mode;
  final String? transporterId;
  final String? transporterName;
  final String? docNo;
  final String? docDate;
  final String? vehicleNo;
  final int? distanceKm;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'transporterId': transporterId,
    'transporterName': transporterName,
    'docNo': docNo,
    'docDate': docDate,
    'vehicleNo': vehicleNo,
    'distanceKm': distanceKm,
  };

  @override
  List<Object?> get props => [mode, transporterId, transporterName, docNo, docDate, vehicleNo, distanceKm];
}

/// Where a document stands with the e-invoice and e-way bill portals, and what is still missing.
class EinvoiceInfo extends Equatable {
  EinvoiceInfo.fromJson(Map<String, dynamic> j)
    : status = j['einvoiceStatus'] as String,
      irn = j['irn'] as String?,
      ackNo = j['ackNo'] as String?,
      ewayBillNo = j['ewayBillNo'] as String?,
      ewayValidUpto = j['ewayValidUpto'] as String?,
      transport = Transport.fromJson(j['transport'] as Map<String, dynamic>),
      einvoiceProblems = (j['einvoiceProblems'] as List).cast<String>(),
      ewayProblems = (j['ewayProblems'] as List).cast<String>(),
      portalConnected = j['portalConnected'] as bool;

  /// none, generated or cancelled.
  final String status;
  final String? irn;
  final String? ackNo;
  final String? ewayBillNo;
  final String? ewayValidUpto;
  final Transport transport;
  final List<String> einvoiceProblems;
  final List<String> ewayProblems;
  final bool portalConnected;

  bool get hasIrn => status == 'generated';

  @override
  List<Object?> get props => [status, irn, ackNo, ewayBillNo, ewayValidUpto, transport, einvoiceProblems, ewayProblems, portalConnected];
}

class PaymentLink extends Equatable {
  PaymentLink.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      url = j['url'] as String,
      amount = j['amount'] as num,
      status = j['status'] as String;

  final String id;
  final String url;
  final num amount;

  /// created, paid, cancelled, expired or failed.
  final String status;

  bool get paid => status == 'paid';

  @override
  List<Object?> get props => [id, url, amount, status];
}

class GoogleLocation extends Equatable {
  GoogleLocation.fromJson(Map<String, dynamic> j)
    : account = j['account'] as String,
      location = j['location'] as String,
      title = j['title'] as String,
      address = j['address'] as String?;

  final String account;
  final String location;
  final String title;
  final String? address;

  @override
  List<Object?> get props => [account, location, title, address];
}

class GoogleProfileInfo extends Equatable {
  GoogleProfileInfo.fromJson(Map<String, dynamic> j)
    : title = (j['title'] as String?) ?? '',
      description = (j['description'] as String?) ?? '',
      website = (j['website'] as String?) ?? '',
      phone = (j['phone'] as String?) ?? '';

  final String title;
  final String description;
  final String website;
  final String phone;

  @override
  List<Object?> get props => [title, description, website, phone];
}

class GoogleReview extends Equatable {
  GoogleReview.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      stars = (j['stars'] as num).toInt(),
      comment = (j['comment'] as String?) ?? '',
      reply = j['reply'] as String?;

  final String id;
  final String name;
  final int stars;
  final String comment;
  final String? reply;

  @override
  List<Object?> get props => [id, name, stars, comment, reply];
}

class GoogleReviews extends Equatable {
  GoogleReviews.fromJson(Map<String, dynamic> j)
    : average = (j['average'] as num?)?.toDouble(),
      total = (j['total'] as num).toInt(),
      reviews = [for (final r in j['reviews'] as List) GoogleReview.fromJson(r as Map<String, dynamic>)];

  final double? average;
  final int total;
  final List<GoogleReview> reviews;

  @override
  List<Object?> get props => [average, total, reviews];
}
