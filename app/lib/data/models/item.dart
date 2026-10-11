import 'package:equatable/equatable.dart';

class Item extends Equatable {
  Item.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String,
        name = j['name'] as String,
        hsnCode = j['hsnCode'] as String?,
        unit = j['unit'] as String?,
        categoryId = j['categoryId'] as String?,
        categoryName = j['categoryName'] as String?,
        itemCode = j['itemCode'] as String?,
        salePrice = j['salePrice'] as num,
        salePriceIncludesTax = j['salePriceIncludesTax'] as bool,
        saleDiscount = j['saleDiscount'] as num,
        saleDiscountType = j['saleDiscountType'] as String,
        wholesalePrice = j['wholesalePrice'] as num?,
        wholesaleMinQty = j['wholesaleMinQty'] as num?,
        purchasePrice = j['purchasePrice'] as num,
        purchasePriceIncludesTax = j['purchasePriceIncludesTax'] as bool,
        gstRate = j['gstRate'] as num?,
        openingQty = j['openingQty'] as num,
        openingPrice = j['openingPrice'] as num?,
        openingDate = j['openingDate'] as String,
        minStock = j['minStock'] as num?,
        location = j['location'] as String?,
        imageFileId = j['imageFileId'] as String?,
        cessRate = j['cessRate'] as num?,
        mrp = j['mrp'] as num?,
        serviceReminderDays = (j['serviceReminderDays'] as num?)?.toInt(),
        stockQty = j['stockQty'] as num,
        stockValue = j['stockValue'] as num,
        lowStock = j['lowStock'] as bool;

  final String id;
  final String type;
  final String name;
  final String? hsnCode;
  final String? unit;
  final String? categoryId;
  final String? categoryName;
  final String? itemCode;
  final num salePrice;
  final bool salePriceIncludesTax;
  final num saleDiscount;
  final String saleDiscountType;
  final num? wholesalePrice;
  final num? wholesaleMinQty;
  final num purchasePrice;
  final bool purchasePriceIncludesTax;
  final num? gstRate;
  final num openingQty;
  final num? openingPrice;
  final String openingDate;
  final num? minStock;
  final String? location;
  final String? imageFileId;

  /// Compensation cess %.
  final num? cessRate;
  final num? mrp;

  /// Services: remind the customer this many days after each sale.
  final int? serviceReminderDays;
  final num stockQty;
  final num stockValue;
  final bool lowStock;

  bool get isProduct => type == 'product';

  @override
  List<Object?> get props => [
        id, type, name, hsnCode, unit, categoryId, categoryName, itemCode, salePrice, salePriceIncludesTax,
        saleDiscount, saleDiscountType, wholesalePrice, wholesaleMinQty, purchasePrice, purchasePriceIncludesTax,
        gstRate, openingQty, openingPrice, openingDate, minStock, location, imageFileId, cessRate, mrp, serviceReminderDays, stockQty, stockValue, lowStock,
      ];
}

class StockMovement extends Equatable {
  StockMovement.fromJson(Map<String, dynamic> j)
      : type = j['type'] as String,
        invoiceId = j['invoiceId'] as String?,
        reference = j['reference'] as String?,
        partyName = j['partyName'] as String?,
        quantity = j['quantity'] as num,
        pricePerUnit = j['pricePerUnit'] as num?,
        date = j['date'] as String,
        notes = j['notes'] as String?;

  final String type;
  final String? invoiceId;
  final String? reference;
  final String? partyName;
  final num quantity;
  final num? pricePerUnit;
  final String date;
  final String? notes;

  String get label => switch (type) {
        'opening' => 'Opening Stock',
        'add' => 'Add Adjustment',
        'reduce' => 'Reduce Adjustment',
        'sale' => 'Sale',
        'purchase' => 'Purchase',
        'credit_note' => 'Sale Return',
        'debit_note' => 'Purchase Return',
        _ => type,
      };

  /// Invoice party for sales/purchases, otherwise the adjustment note.
  String get details => partyName ?? notes ?? '';

  @override
  List<Object?> get props => [type, invoiceId, reference, partyName, quantity, pricePerUnit, date, notes];
}

/// Stock of an item in one batch.
class ItemBatch extends Equatable {
  ItemBatch.fromJson(Map<String, dynamic> j)
      : batchNo = j['batchNo'] as String,
        expiryDate = j['expiryDate'] as String?,
        mrp = j['mrp'] as num?,
        quantity = j['quantity'] as num;
  final String batchNo;
  final String? expiryDate;
  final num? mrp;
  final num quantity;

  @override
  List<Object?> get props => [batchNo, expiryDate, mrp, quantity];
}

/// A store. [id] is null for the main store.
class Godown extends Equatable {
  Godown.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String?,
        name = j['name'] as String,
        address = j['address'] as String?,
        itemCount = ((j['itemCount'] as num?) ?? 0).toInt(),
        stockValue = (j['stockValue'] as num?) ?? 0;
  final String? id;
  final String name;
  final String? address;
  final int itemCount;
  final num stockValue;

  bool get isMain => id == null;

  @override
  List<Object?> get props => [id, name, address, itemCount, stockValue];
}

/// What a store holds of one item (or what an item has in one store).
class GodownStock extends Equatable {
  const GodownStock({this.itemId, this.godownId, required this.name, this.unit, required this.quantity, this.value = 0});
  final String? itemId;
  final String? godownId;
  final String name;
  final String? unit;
  final num quantity;
  final num value;

  @override
  List<Object?> get props => [itemId, godownId, name, unit, quantity, value];
}

class Category extends Equatable {
  Category.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        itemCount = (j['itemCount'] as num?) ?? 0;
  final String id;
  final String name;
  final num itemCount;

  @override
  List<Object?> get props => [id, name, itemCount];
}

class Unit extends Equatable {
  Unit.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        shortName = j['shortName'] as String;
  final String id;
  final String name;
  final String shortName;

  @override
  List<Object?> get props => [id, name, shortName];
}

const gstRateOptions = <num>[0, 0.1, 0.25, 1.5, 3, 5, 6, 12, 18, 28, 40];
