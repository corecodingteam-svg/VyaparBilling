import 'dart:async';

/// Kinds of data a write can change.
enum DataTopic { parties, items, catalog, invoices, payments, expenses, accounts, loans, firm, journals }

/// App-wide notifications that data changed. Repositories publish after every write; blocs subscribe
/// to the topics their screens depend on (e.g. a party's balance depends on invoices and payments).
class ChangeBus {
  final _controller = StreamController<DataTopic>.broadcast();

  void publish(DataTopic topic) => _controller.add(topic);

  Stream<void> on(Set<DataTopic> topics) => _controller.stream.where(topics.contains);
}
