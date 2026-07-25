class UserProfile {
  final String name;
  final double baseSalary; // Need this for the Triangle logic later!
  final String currency;   // USD or MYR

  UserProfile({
    required this.name, 
    required this.baseSalary, 
    this.currency = 'USD'
  });
}