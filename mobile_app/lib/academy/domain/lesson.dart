class Lesson {
  final String id;
  final String title;
  final String description;
  final String difficulty; // 'Beginner', 'Intermediate', 'Advanced'
  final int xpReward;
  final String riskProfileMatch; // 'Conservative', 'Moderate', 'Aggressive', 'All'

  Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.xpReward,
    required this.riskProfileMatch,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'difficulty': difficulty,
    'xpReward': xpReward,
    'riskProfileMatch': riskProfileMatch,
  };

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    difficulty: json['difficulty'],
    xpReward: json['xpReward'],
    riskProfileMatch: json['riskProfileMatch'],
  );
}