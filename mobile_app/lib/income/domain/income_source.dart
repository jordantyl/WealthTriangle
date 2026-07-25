class IncomeSource {
  final String name;       // e.g., "Grab Driving", "Dividend"
  final double amount;     // e.g., 500.00
  final bool isMonthly;    // true = Monthly, false = Yearly

  IncomeSource({
    required this.name,
    required this.amount,
    required this.isMonthly,
  });
}