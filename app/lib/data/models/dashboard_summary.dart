import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  DashboardSummary.fromJson(Map<String, dynamic> j)
      : cashInHand = (j['cashInHand'] as num?) ?? 0,
        bankBalance = (j['bankBalance'] as num?) ?? 0,
        receivable = j['receivable'] as num,
        receivableParties = j['receivableParties'] as num,
        payable = j['payable'] as num,
        payableParties = j['payableParties'] as num,
        lowStockItems = j['lowStockItems'] as num,
        salesTotal = (j['sales'] as Map)['total'] as num,
        salesFrom = (j['sales'] as Map)['from'] as String,
        salesTo = (j['sales'] as Map)['to'] as String,
        dailySales = {
          for (final d in (j['sales'] as Map)['daily'] as List) d['date'] as String: d['amount'] as num,
        };

  final num cashInHand;
  final num bankBalance;
  final num receivable;
  final num receivableParties;
  final num payable;
  final num payableParties;
  final num lowStockItems;
  final num salesTotal;
  final String salesFrom;
  final String salesTo;

  /// 'YYYY-MM-DD' → sale total; days without sales are absent.
  final Map<String, num> dailySales;

  @override
  List<Object?> get props => [cashInHand, bankBalance, receivable, receivableParties, payable, payableParties, lowStockItems, salesTotal, salesFrom, salesTo, dailySales];
}
