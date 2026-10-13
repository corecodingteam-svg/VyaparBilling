import 'package:equatable/equatable.dart';

class AdditionalField extends Equatable {
  const AdditionalField(this.name, this.value);
  final String name;
  final String value;

  @override
  List<Object?> get props => [name, value];
}

class Party extends Equatable {
  Party.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String?,
        gstin = j['gstin'] as String?,
        gstType = j['gstType'] as String,
        stateCode = j['stateCode'] as String?,
        email = j['email'] as String?,
        billingAddress = j['billingAddress'] as String?,
        shippingAddress = j['shippingAddress'] as String?,
        city = j['city'] as String?,
        pincode = j['pincode'] as String?,
        openingBalance = j['openingBalance'] as num,
        openingBalanceDate = j['openingBalanceDate'] as String,
        creditLimit = j['creditLimit'] as num?,
        additionalFields = [
          for (final f in (j['additionalFields'] as List)) AdditionalField(f['name'] as String, f['value'] as String),
        ],
        groupId = j['groupId'] as String?,
        groupName = j['groupName'] as String?,
        assignedUserId = j['assignedUserId'] as String?,
        assignedUserName = j['assignedUserName'] as String?,
        currencyCode = j['currencyCode'] as String?,
        loyaltyOpening = ((j['loyaltyOpening'] as num?) ?? 0).toInt(),
        loyaltyPoints = ((j['loyaltyPoints'] as num?) ?? 0).toInt(),
        fxBalance = j['fxBalance'] as num?,
        balance = j['balance'] as num;

  final String id;
  final String name;
  final String? phone;
  final String? gstin;
  final String gstType;
  final String? stateCode;
  final String? email;
  final String? billingAddress;
  final String? shippingAddress;
  final String? city;
  final String? pincode;
  final num openingBalance;
  final String openingBalanceDate;
  final num? creditLimit;
  final List<AdditionalField> additionalFields;
  final String? groupId;
  final String? groupName;

  /// The salesman this party belongs to.
  final String? assignedUserId;
  final String? assignedUserName;

  /// A foreign party is billed and pays in this currency.
  final String? currencyCode;
  final int loyaltyOpening;

  /// Loyalty points the party can redeem now.
  final int loyaltyPoints;

  /// For a foreign party: what they owe in their own currency.
  final num? fxBalance;
  final num balance;

  @override
  List<Object?> get props => [
        id, name, phone, gstin, gstType, stateCode, email, billingAddress, shippingAddress, city, pincode,
        openingBalance, openingBalanceDate, creditLimit, additionalFields, balance, groupId, groupName, assignedUserId, assignedUserName,
        currencyCode, loyaltyOpening, loyaltyPoints, fxBalance,
      ];
}

class PartyTxn extends Equatable {
  PartyTxn.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String?,
        kind = (j['kind'] as String?) ?? 'opening',
        type = j['type'] as String,
        number = j['number'] as String?,
        date = j['date'] as String,
        total = j['total'] as num,
        balance = j['balance'] as num;

  /// Invoice or payment id; null for the opening balance.
  final String? id;

  /// opening | sale | purchase | credit_note | debit_note | payment_in | payment_out
  final String kind;
  final String type;
  final String? number;
  final String date;
  final num total;

  /// Party's running balance after this entry.
  final num balance;

  @override
  List<Object?> get props => [id, kind, type, number, date, total, balance];
}

class PartyGroup extends Equatable {
  PartyGroup.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        partyCount = ((j['partyCount'] as num?) ?? 0).toInt();
  final String id;
  final String name;
  final int partyCount;

  @override
  List<Object?> get props => [id, name, partyCount];
}

const gstTypes = {
  'unregistered': 'Unregistered/Consumer',
  'regular': 'Registered Business - Regular',
  'composition': 'Registered Business - Composition',
};
