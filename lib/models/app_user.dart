class AppUser {
  final String id;
  final String name;  // or String?
  final String? email; // <- make this nullable

  AppUser({
    required this.id,
    required this.name,
    this.email,
  });
}

class NumberDetails {
  final String carrier;
  final String location;

  NumberDetails({required this.carrier, required this.location});
}


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