import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/payments_repository.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

class LinkPaymentsState extends Equatable {
  const LinkPaymentsState({this.status = LoadStatus.loading, this.due = 0, this.payments = const [], this.amounts = const {}, this.saving = false, this.saved = false, this.error});

  final LoadStatus status;
  final num due;
  final List<LinkablePayment> payments;

  /// Typed amount per payment id.
  final Map<String, String> amounts;
  final bool saving;
  final bool saved;
  final String? error;

  num get linked => _r2(amounts.values.fold<num>(0, (s, v) => s + (parseNum(v) ?? 0)));
  num get remaining => _r2(due - linked);

  /// Why the amounts cannot be saved as typed, if they cannot.
  String? get problem {
    if (linked > due) return 'That is ${money(_r2(linked - due))} more than is left to pay.';
    for (final p in payments) {
      if ((parseNum(amounts[p.paymentId] ?? '') ?? 0) > p.free) return 'Receipt ${p.number} only has ${money(p.free)} free.';
    }
    return null;
  }

  LinkPaymentsState copyWith({Map<String, String>? amounts, bool? saving, bool? saved, String? error}) => LinkPaymentsState(
    status: status,
    due: due,
    payments: payments,
    amounts: amounts ?? this.amounts,
    saving: saving ?? this.saving,
    saved: saved ?? this.saved,
    error: error,
  );

  @override
  List<Object?> get props => [status, due, payments, amounts, saving, saved, error];
}

num _r2(num v) => (v * 100).round() / 100;

/// Sets a party's payments against one document, from the document's side.
class LinkPaymentsCubit extends Cubit<LinkPaymentsState> {
  LinkPaymentsCubit(this._repo, this.invoiceId) : super(const LinkPaymentsState());
  final PaymentsRepository _repo;
  final String invoiceId;

  Future<void> load() async {
    try {
      final l = await _repo.linkable(invoiceId);
      emit(LinkPaymentsState(
        status: LoadStatus.success,
        due: l.due,
        payments: l.payments,
        amounts: {for (final p in l.payments) if (p.linked > 0) p.paymentId: numText(p.linked)},
      ));
    } catch (e) {
      emit(LinkPaymentsState(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void amountChanged(String paymentId, String text) => emit(state.copyWith(amounts: {...state.amounts, paymentId: text}));

  /// Uses the payments oldest first until the document is settled.
  void fill() {
    var left = state.due;
    final amounts = <String, String>{};
    for (final p in state.payments) {
      final take = left < p.free ? left : p.free;
      if (take > 0) amounts[p.paymentId] = numText(_r2(take));
      left = _r2(left - take);
    }
    emit(state.copyWith(amounts: amounts));
  }

  Future<void> save() async {
    if (state.saving || state.problem != null) return;
    emit(state.copyWith(saving: true));
    try {
      await _repo.linkToInvoice(invoiceId, {for (final e in state.amounts.entries) e.key: parseNum(e.value) ?? 0});
      emit(state.copyWith(saving: false, saved: true));
    } catch (e) {
      emit(state.copyWith(saving: false, error: ApiException.from(e).message));
    }
  }
}

/// Lets the user set the party's unlinked payments against this document.
Future<void> showLinkPaymentsDialog(BuildContext context, {required String invoiceId, required String title}) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider(
    create: (ctx) => LinkPaymentsCubit(context.read<PaymentsRepository>(), invoiceId)..load(),
    child: BlocConsumer<LinkPaymentsCubit, LinkPaymentsState>(
      listenWhen: (a, b) => a.saved != b.saved || (b.error != null && a.error != b.error && b.status == LoadStatus.success),
      listener: (ctx, s) {
        if (s.saved) {
          Navigator.pop(ctx);
          showSuccess(context, 'Payments linked');
        } else if (s.error != null) {
          showError(ctx, s.error!);
        }
      },
      builder: (ctx, s) {
        final cubit = ctx.read<LinkPaymentsCubit>();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: AppSize.dialogMd,
            child: switch (s.status) {
              LoadStatus.failure => Text(s.error ?? 'Could not load'),
              LoadStatus.success => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('To settle: ${money(s.due)}   ·   Linked: ${money(s.linked)}   ·   Left: ${money(s.remaining)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpace.sm),
                  if (s.payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                      child: Text('This party has no payment with an amount left to link. Record a payment first.', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in s.payments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                            child: Row(
                              children: [
                                Expanded(child: Text('${p.number} · ${displayDate(p.date)}\n${money(p.amount)}, ${money(p.free)} free', style: AppText.body)),
                                SizedBox(
                                  width: AppSize.fieldXs,
                                  child: TextFormField(
                                    key: ValueKey('${p.paymentId}-${s.amounts[p.paymentId] == null}'),
                                    initialValue: s.amounts[p.paymentId] ?? '',
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.end,
                                    decoration: const InputDecoration(labelText: 'Link', isDense: true),
                                    onChanged: (v) => cubit.amountChanged(p.paymentId, v),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (s.problem != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(s.problem!, style: const TextStyle(color: AppColors.dangerText))),
                ],
              ),
              _ => const LoadingView(),
            },
          ),
          actions: [
            if (s.payments.isNotEmpty) TextButton(onPressed: cubit.fill, child: const Text('Fill automatically')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: s.status != LoadStatus.success || s.saving || s.problem != null ? null : cubit.save, child: const Text('Save')),
          ],
        );
      },
    ),
  ),
);
