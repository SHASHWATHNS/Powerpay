class TransactionItem {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final DateTime date;

  TransactionItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.date,
  });
}
