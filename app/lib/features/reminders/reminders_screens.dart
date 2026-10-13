import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../data/models/extras.dart';
import '../../data/models/invoice.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/utilities_repository.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import '../company/firm_cubit.dart';
import '../integrations/integrations_screens.dart';
import '../payments/payment_form_dialog.dart';

/// Digits of an Indian mobile number in international form, or null when [phone] is not one.
String? whatsappNumber(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return digits;
  return null;
}

/// Opens WhatsApp with [message] ready to send to [phone]. Nothing is sent until the user presses send there.
Future<void> _openWhatsApp(BuildContext context, String? phone, String message) async {
  final number = whatsappNumber(phone);
  if (number == null) return showError(context, 'This party has no valid mobile number. Use "Copy message" instead.');
  final ok = await launchUrl(Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showError(context, 'Could not open WhatsApp.');
}

Future<void> _copy(BuildContext context, String message) async {
  await Clipboard.setData(ClipboardData(text: message));
  if (context.mounted) showSuccess(context, 'Message copied');
}

List<Widget> _messageActions(BuildContext context, String? phone, String message) => [
      IconButton(tooltip: 'Remind on WhatsApp', icon: const Icon(Icons.chat_outlined, size: 20), onPressed: () => _openWhatsApp(context, phone, message)),
      IconButton(tooltip: 'Copy message', icon: const Icon(Icons.copy, size: 18), onPressed: () => _copy(context, message)),
    ];

/// Customers with invoices past their due date.
class PaymentRemindersScreen extends StatelessWidget {
  const PaymentRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ListCubit<PaymentReminder>(
          ctx.read<UtilitiesRepository>().paymentReminders,
          bus: ctx.read<ChangeBus>(),
          topics: const {DataTopic.invoices, DataTopic.payments, DataTopic.firm},
        )..load(),
        child: ListCubitView<PaymentReminder>(builder: (context, state) {
          final settings = settingsOf(context, listen: true);
          final firmName = context.select((AuthBloc b) => b.state.user?.firmName ?? '');
          final total = state.items.fold<num>(0, (s, r) => s + r.overdueAmount);
          if (settings.paymentReminderDays == null) {
            return TitledPage(title: 'Payment Reminders', children: [
              Card(
                child: SizedBox(
                  height: 260,
                  child: EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'Payment reminders are switched off',
                    message: 'Turn them on under Settings › Party.',
                    action: OutlinedButton(onPressed: () => context.go('/settings'), child: const Text('Open Settings')),
                  ),
                ),
              ),
            ]);
          }
          return TitledPage(
            title: 'Payment Reminders',
            subtitle: 'Customers with sale invoices past their due date'
                '${settings.dueDatesEnabled ? '' : ' (unpaid for more than ${settings.paymentReminderDays} days)'}. Overdue in all: ${money(total)}.',
            children: [
              RowsCard(
                empty: const EmptyState(icon: Icons.thumb_up_alt_outlined, title: 'Nothing overdue', message: 'No customer has an invoice past its due date.'),
                rows: [
                  for (final r in state.items)
                    ListTile(
                      title: Text(r.name),
                      subtitle: Text('${r.invoices} invoice${r.invoices == 1 ? '' : 's'} · due since ${displayDate(r.oldestDue)} · ${r.daysOverdue} days overdue'
                          '${(r.phone ?? '').isEmpty ? '' : ' · ${r.phone}'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money(r.overdueAmount), style: const TextStyle(fontWeight: FontWeight.w700, color: payRed)),
                          if (r.balance != r.overdueAmount) Text('of ${money(r.balance)} owed', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ]),
                        const SizedBox(width: 4),
                        ..._messageActions(
                          context,
                          r.phone,
                          'Dear ${r.name}, this is a gentle reminder that ${money(r.overdueAmount)} is overdue for payment to $firmName. '
                          'Kindly pay at the earliest. Thank you.',
                        ),
                        IconButton(
                          tooltip: 'Send reminder from the app',
                          icon: const Icon(Icons.send_outlined, size: 20),
                          onPressed: () => showSendDialog(
                            context,
                            title: 'Remind ${r.name}',
                            phone: r.phone,
                            manualMessage: 'Dear ${r.name}, this is a gentle reminder that ${money(r.overdueAmount)} is overdue for payment to $firmName. Kindly pay at the earliest. Thank you.',
                            send: (repo, channel, phone) => repo.sendReminder(r.partyId, r.overdueAmount, channel, phone: phone),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Record payment',
                          icon: const Icon(Icons.payments_outlined, size: 20),
                          onPressed: () => showPaymentForm(context, PaymentKind.paymentIn, partyId: r.partyId),
                        ),
                      ]),
                    ),
                ],
              ),
            ],
          );
        }),
      );
}

/// Services sold whose follow-up is due soon or overdue.
class ServiceRemindersScreen extends StatelessWidget {
  const ServiceRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ListCubit<ServiceReminder>(ctx.read<UtilitiesRepository>().serviceReminders, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.invoices, DataTopic.items})
          ..load(),
        child: ListCubitView<ServiceReminder>(builder: (context, state) {
          final cubit = context.read<ListCubit<ServiceReminder>>();
          final repo = context.read<UtilitiesRepository>();
          final firmName = context.select((AuthBloc b) => b.state.user?.firmName ?? '');
          return TitledPage(
            title: 'Service Reminders',
            subtitle: 'Follow-ups due in the next 30 days or already overdue. Set "Service reminder after" on a service item to get them.',
            children: [
              RowsCard(
                empty: const EmptyState(
                  icon: Icons.build_circle_outlined,
                  title: 'No service follow-ups due',
                  message: 'Reminders appear here after you sell a service that has a reminder period.',
                ),
                rows: [
                  for (final r in state.items)
                    ListTile(
                      onTap: () => context.push('${InvoiceKind.sale.basePath}/${r.invoiceId}/edit'),
                      title: Text('${r.itemName}  ·  ${r.partyName}'),
                      subtitle: Text('Sold on ${displayDate(r.soldOn)} (invoice ${r.invoiceNumber})${(r.phone ?? '').isEmpty ? '' : ' · ${r.phone}'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(displayDate(r.dueDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            r.daysLeft < 0 ? '${-r.daysLeft} days overdue' : (r.daysLeft == 0 ? 'due today' : 'in ${r.daysLeft} days'),
                            style: TextStyle(fontSize: 11, color: r.daysLeft <= 0 ? payRed : Colors.black54),
                          ),
                        ]),
                        const SizedBox(width: 4),
                        ..._messageActions(
                          context,
                          r.phone,
                          'Dear ${r.partyName}, your ${r.itemName} is due on ${displayDate(r.dueDate)}. Please contact $firmName to schedule it. Thank you.',
                        ),
                        IconButton(
                          tooltip: 'Mark as done',
                          icon: const Icon(Icons.check_circle_outline, size: 20, color: receiveGreen),
                          onPressed: state.busy ? null : () => cubit.run(() => repo.markServiceDone(r.id)),
                        ),
                      ]),
                    ),
                ],
              ),
            ],
          );
        }),
      );
}
