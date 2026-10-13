import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/integrations.dart';

/// Outside services the company connects: WhatsApp and SMS messages, e-invoice and e-way bill,
/// online payments and the Google Business Profile.
class IntegrationsRepository {
  IntegrationsRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  String? _blankToNull(String? s) => s == null || s.isEmpty ? null : s;

  List<Integration> _list(dynamic json) => [for (final j in json as List) Integration.fromJson(j as Map<String, dynamic>)];

  Future<List<Integration>> integrations() async => _list(await _api.get<List<dynamic>>('/integrations'));

  Future<List<Integration>> save(String provider, Map<String, String> values) async =>
      _list(await _api.put<List<dynamic>>('/integrations/$provider', {'values': values}));

  Future<void> disconnect(String provider) => _api.delete('/integrations/$provider');

  Future<String> webhookUrl() async => (await _api.get<Map<String, dynamic>>('/online-payments/webhook-url'))['url'] as String;

  // ---------------------------------------------------------------- messages

  Future<void> testMessage(String channel, String to) => _api.post<dynamic>('/messages/test', {'channel': channel, 'to': to});

  Future<void> sendInvoice(String id, String channel, {String? phone}) =>
      _api.post<dynamic>('/messages/invoices/$id', {'channel': channel, 'phone': ?_blankToNull(phone)});

  Future<void> sendPayment(String id, String channel, {String? phone}) =>
      _api.post<dynamic>('/messages/payments/$id', {'channel': channel, 'phone': ?_blankToNull(phone)});

  Future<void> sendReminder(String partyId, num amount, String channel, {String? phone}) =>
      _api.post<dynamic>('/messages/reminders', {'partyId': partyId, 'amount': amount, 'channel': channel, 'phone': ?_blankToNull(phone)});

  /// Returns how many were sent and the names of those that failed.
  Future<({int recipients, int sent, List<String> failed})> marketing(String channel, String text, {String? groupId}) async {
    final j = await _api.post<Map<String, dynamic>>('/messages/marketing', {'channel': channel, 'text': text, 'groupId': ?groupId});
    return (
      recipients: (j['recipients'] as num).toInt(),
      sent: (j['sent'] as num).toInt(),
      failed: [for (final f in j['failed'] as List) '${f['name']}: ${f['error']}'],
    );
  }

  Future<List<MessageEntry>> messages() async =>
      [for (final j in await _api.get<List<dynamic>>('/messages')) MessageEntry.fromJson(j as Map<String, dynamic>)];

  // ---------------------------------------------------------------- e-invoice and e-way bill

  Future<EinvoiceInfo> einvoice(String invoiceId) async => EinvoiceInfo.fromJson(await _api.get<Map<String, dynamic>>('/einvoice/$invoiceId'));

  EinvoiceInfo _info(Map<String, dynamic> j) {
    _bus.publish(DataTopic.invoices);
    return EinvoiceInfo.fromJson(j);
  }

  Future<EinvoiceInfo> saveTransport(String invoiceId, Transport t) async => _info(await _api.put<Map<String, dynamic>>('/einvoice/$invoiceId/transport', t.toJson()));

  Future<EinvoiceInfo> generateEinvoice(String invoiceId) async => _info(await _api.post<Map<String, dynamic>>('/einvoice/$invoiceId/generate'));

  Future<EinvoiceInfo> recordIrn(String invoiceId, {required String irn, String? ackNo, String? ackDate}) async => _info(
    await _api.post<Map<String, dynamic>>('/einvoice/$invoiceId/record', {'irn': irn, 'ackNo': ?_blankToNull(ackNo), 'ackDate': ?_blankToNull(ackDate)}),
  );

  Future<EinvoiceInfo> cancelEinvoice(String invoiceId, {required String reason, required String remark, required bool onPortal}) async =>
      _info(await _api.post<Map<String, dynamic>>('/einvoice/$invoiceId/cancel', {'reason': reason, 'remark': remark, 'onPortal': onPortal}));

  Future<EinvoiceInfo> generateEway(String invoiceId) async => _info(await _api.post<Map<String, dynamic>>('/einvoice/$invoiceId/eway/generate'));

  Future<EinvoiceInfo> recordEway(String invoiceId, String no) async => _info(await _api.post<Map<String, dynamic>>('/einvoice/$invoiceId/eway/record', {'no': no}));

  /// The JSON to upload on the portal: (file name, JSON value).
  Future<(String, Object)> einvoiceJson(String invoiceId) async {
    final j = await _api.get<Map<String, dynamic>>('/einvoice/$invoiceId/einvoice-json');
    return (j['fileName'] as String, j['json'] as Object);
  }

  Future<(String, Object)> ewayJson(String invoiceId) async {
    final j = await _api.get<Map<String, dynamic>>('/einvoice/$invoiceId/eway-json');
    return (j['fileName'] as String, j['json'] as Object);
  }

  // ---------------------------------------------------------------- online payments

  Future<List<PaymentLink>> paymentLinks(String invoiceId) async =>
      [for (final j in await _api.get<List<dynamic>>('/online-payments/invoices/$invoiceId')) PaymentLink.fromJson(j as Map<String, dynamic>)];

  Future<PaymentLink> createPaymentLink(String invoiceId) async => PaymentLink.fromJson(await _api.post<Map<String, dynamic>>('/online-payments/invoices/$invoiceId/link'));

  /// Asks the provider whether the link was paid; a payment found is recorded.
  Future<PaymentLink> refreshPaymentLink(String linkId) async {
    final link = PaymentLink.fromJson(await _api.post<Map<String, dynamic>>('/online-payments/links/$linkId/refresh'));
    if (link.paid) {
      _bus.publish(DataTopic.payments);
      _bus.publish(DataTopic.invoices);
    }
    return link;
  }

  // ---------------------------------------------------------------- Google Business Profile

  Future<String> googleAuthUrl() async => (await _api.get<Map<String, dynamic>>('/google-profile/auth-url'))['url'] as String;

  Future<List<GoogleLocation>> googleLocations() async =>
      [for (final j in await _api.get<List<dynamic>>('/google-profile/locations')) GoogleLocation.fromJson(j as Map<String, dynamic>)];

  Future<void> chooseGoogleLocation(GoogleLocation l) =>
      _api.post<dynamic>('/google-profile/location', {'account': l.account, 'location': l.location, 'title': l.title});

  Future<GoogleProfileInfo> googleProfile() async => GoogleProfileInfo.fromJson(await _api.get<Map<String, dynamic>>('/google-profile/profile'));

  Future<GoogleProfileInfo> saveGoogleProfile({String? description, String? website}) async => GoogleProfileInfo.fromJson(
    await _api.put<Map<String, dynamic>>('/google-profile/profile', {'description': ?description, 'website': ?website}),
  );

  Future<void> googlePost(String summary, {String? url}) => _api.post<dynamic>('/google-profile/posts', {'summary': summary, 'learnMoreUrl': ?_blankToNull(url)});

  Future<GoogleReviews> googleReviews() async => GoogleReviews.fromJson(await _api.get<Map<String, dynamic>>('/google-profile/reviews'));

  Future<void> replyToReview(String reviewId, String comment) => _api.post<dynamic>('/google-profile/reviews/reply', {'reviewId': reviewId, 'comment': comment});
}
