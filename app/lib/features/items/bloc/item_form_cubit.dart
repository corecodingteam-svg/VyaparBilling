import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/models/firm.dart';
import '../../../data/models/item.dart';
import '../../../data/repositories/items_repository.dart';
import '../../../shared/format.dart';

enum ItemFormResult { none, saved, savedAndNew, deleted }

/// Non-text state of the add/edit item dialog. Text fields live in controllers owned by the widget.
class ItemFormState extends Equatable {
  const ItemFormState({
    required this.type,
    this.unit,
    this.categoryId,
    this.saleIncludesTax = false,
    this.discountType = 'percent',
    this.wholesale = false,
    this.purchaseIncludesTax = false,
    this.gstRate,
    required this.openingDate,
    this.imageFileId,
    this.status = SubmitStatus.idle,
    this.result = ItemFormResult.none,
    this.error,
  });

  /// [defaultUnit] is the unit new items start with (from settings).
  factory ItemFormState.from(Item? i, String type, {String defaultUnit = ''}) => ItemFormState(
    type: i?.type ?? type,
    unit: i == null ? (defaultUnit.isEmpty ? null : defaultUnit) : i.unit,
    imageFileId: i?.imageFileId,
    categoryId: i?.categoryId,
    saleIncludesTax: i?.salePriceIncludesTax ?? false,
    discountType: i?.saleDiscountType ?? 'percent',
    wholesale: i?.wholesalePrice != null,
    purchaseIncludesTax: i?.purchasePriceIncludesTax ?? false,
    gstRate: i?.gstRate,
    openingDate: i?.openingDate ?? isoDate(DateTime.now()),
  );

  final String type;
  final String? unit;
  final String? categoryId;
  final bool saleIncludesTax;
  final String discountType;
  final bool wholesale;
  final bool purchaseIncludesTax;
  final num? gstRate;
  final String openingDate;
  final String? imageFileId;
  final SubmitStatus status;
  final ItemFormResult result;
  final String? error;

  bool get isProduct => type == 'product';

  ItemFormState copyWith({
    String? type,
    String? Function()? unit,
    String? Function()? categoryId,
    bool? saleIncludesTax,
    String? discountType,
    bool? wholesale,
    bool? purchaseIncludesTax,
    num? Function()? gstRate,
    String? openingDate,
    String? Function()? imageFileId,
    SubmitStatus? status,
    ItemFormResult? result,
    String? error,
  }) => ItemFormState(
    type: type ?? this.type,
    unit: unit != null ? unit() : this.unit,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    saleIncludesTax: saleIncludesTax ?? this.saleIncludesTax,
    discountType: discountType ?? this.discountType,
    wholesale: wholesale ?? this.wholesale,
    purchaseIncludesTax: purchaseIncludesTax ?? this.purchaseIncludesTax,
    gstRate: gstRate != null ? gstRate() : this.gstRate,
    openingDate: openingDate ?? this.openingDate,
    imageFileId: imageFileId != null ? imageFileId() : this.imageFileId,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error,
  );

  @override
  List<Object?> get props => [
    type,
    unit,
    categoryId,
    saleIncludesTax,
    discountType,
    wholesale,
    purchaseIncludesTax,
    gstRate,
    openingDate,
    imageFileId,
    status,
    result,
    error,
  ];
}

class ItemFormCubit extends Cubit<ItemFormState> {
  ItemFormCubit(this._repo, this.item, String type, {this.settings = const FirmSettings()})
    : super(ItemFormState.from(item, type, defaultUnit: settings.defaultUnit));

  final ItemsRepository _repo;
  final Item? item;

  /// The business's item settings: default unit, whether wholesale prices and service reminders are used.
  final FirmSettings settings;

  bool get editing => item != null;

  void typeChanged(String v) => emit(state.copyWith(type: v));
  void unitChanged(String? v) => emit(state.copyWith(unit: () => v));
  void categoryChanged(String? v) => emit(state.copyWith(categoryId: () => v));
  void saleTaxChanged(bool v) => emit(state.copyWith(saleIncludesTax: v));
  void discountTypeChanged(String v) => emit(state.copyWith(discountType: v));
  void wholesaleToggled(bool v) => emit(state.copyWith(wholesale: v));
  void purchaseTaxChanged(bool v) => emit(state.copyWith(purchaseIncludesTax: v));
  void gstRateChanged(num? v) => emit(state.copyWith(gstRate: () => v));
  void openingDateChanged(String v) => emit(state.copyWith(openingDate: v));
  void imageChanged(String? fileId) => emit(state.copyWith(imageFileId: () => fileId));

  /// [fields] holds the parsed text-field values; the cubit adds its own selections.
  Future<void> save(Map<String, dynamic> fields, {required bool andNew}) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting, result: ItemFormResult.none));
    final s = state;
    try {
      await _repo.save(item?.id, {
        'type': s.type,
        'name': fields['name'],
        'hsnCode': fields['hsnCode'],
        'itemCode': fields['itemCode'],
        'unit': s.unit,
        'categoryId': s.categoryId,
        'salePrice': fields['salePrice'] ?? 0,
        'salePriceIncludesTax': s.saleIncludesTax,
        'saleDiscount': fields['saleDiscount'] ?? 0,
        'saleDiscountType': s.discountType,
        'wholesalePrice': s.wholesale ? fields['wholesalePrice'] : null,
        'wholesaleMinQty': s.wholesale ? fields['wholesaleMinQty'] : null,
        'purchasePrice': fields['purchasePrice'] ?? 0,
        'purchasePriceIncludesTax': s.purchaseIncludesTax,
        'gstRate': s.gstRate,
        'imageFileId': s.imageFileId,
        // Only sent when the business uses them (or the item already has a value), so they are never cleared by accident.
        if (settings.cessEnabled || item?.cessRate != null) 'cessRate': fields['cessRate'],
        if (settings.mrpEnabled || item?.mrp != null) 'mrp': fields['mrp'],
        // Only services have follow-up reminders.
        'serviceReminderDays': s.isProduct ? null : fields['serviceReminderDays'],
        if (s.isProduct) ...{
          'openingQty': fields['openingQty'] ?? 0,
          'openingPrice': fields['openingPrice'],
          'openingDate': s.openingDate,
          'minStock': fields['minStock'],
          'location': fields['location'],
        },
      });
      emit(
        andNew
            ? ItemFormState.from(
                null,
                s.type,
                defaultUnit: settings.defaultUnit,
              ).copyWith(status: SubmitStatus.success, result: ItemFormResult.savedAndNew)
            : state.copyWith(status: SubmitStatus.success, result: ItemFormResult.saved),
      );
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> delete() async {
    emit(state.copyWith(status: SubmitStatus.submitting, result: ItemFormResult.none));
    try {
      await _repo.delete(item!.id);
      emit(state.copyWith(status: SubmitStatus.success, result: ItemFormResult.deleted));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
