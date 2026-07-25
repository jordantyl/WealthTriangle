class LiquidityEvent {
  final String id;
  final String title;
  final double amount;
  final DateTime maturityDate;
  final String type; // 'fixed_deposit' or 'bond'

  LiquidityEvent({
    required this.id,
    required this.title,
    required this.amount,
    required this.maturityDate,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'maturityDate': maturityDate.toIso8601String(),
    'type': type,
  };

  factory LiquidityEvent.fromJson(Map<String, dynamic> json) => LiquidityEvent(
    id: json['id'],
    title: json['title'],
    amount: json['amount'],
    maturityDate: DateTime.parse(json['maturityDate']),
    type: json['type'],
  );

  int get daysUntil => maturityDate.difference(DateTime.now()).inDays;
  bool get isUpcoming => daysUntil >= 0;
}